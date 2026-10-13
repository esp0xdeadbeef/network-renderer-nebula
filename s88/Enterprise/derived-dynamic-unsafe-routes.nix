{ lib
, helpers
, cpmData
, siteCpm
, overlayName
, overlayCpm
,
}:

let
  inherit (helpers)
    sortedAttrNames
    stripPrefixLength
    ;

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];

  dynamicFirewallCidrsForInterfaceIn = siteCpmForInterface: import ./derived-dynamic-firewall-cidrs.nix {
    inherit lib overlayName;
    siteCpm = siteCpmForInterface;
  };

  peerSiteCpmFor = peerSite:
    let
      parts = lib.splitString "." peerSite;
    in
    if builtins.length parts != 2 then
      { }
    else
      attrsOrEmpty ((cpmData.${builtins.elemAt parts 0} or { }).${builtins.elemAt parts 1} or null);

  # The peer site's modeled overlay participant address -- the next hop for the
  # overlay reachability routes toward that peer (URS: "Overlay transport shall
  # model endpoint identity, permitted peers, ...").  A peer site is not
  # necessarily compiled in this site's pass, so the address is modeled
  # canonically on this overlay's provider block (nebula.lighthouse.addr4/6).
  # The CPM emits it; the renderer must only read it, never invent it (SMS-070).
  overlayCpmRecord = attrsOrEmpty ((overlayCpm.overlays or { }).${overlayName} or null);
  peerOverlayAddress =
    let
      lh = attrsOrEmpty ((overlayCpmRecord.nebula or { }).lighthouse or null);
    in
    {
      ipv4 = lh.addr4 or null;
      ipv6 = lh.addr6 or null;
    };

  peerViaFor =
    family:
    let
      raw = if family == "ipv4" then peerOverlayAddress.ipv4 else peerOverlayAddress.ipv6;
    in
    if builtins.isString raw && raw != "" then raw else null;

  targetDynamicFirewallCidrsIn =
    peerSiteCpm: nodeName: target:
    let
      dynamicFirewallCidrsForPeerInterface = dynamicFirewallCidrsForInterfaceIn peerSiteCpm;
      interfaces = attrsOrEmpty ((target.effectiveRuntimeRealization or { }).interfaces or null);
      matchingInterfaces =
        lib.filter
          (iface: (iface.logicalNode or null) == nodeName && ((iface.backingRef or { }).name or null) == overlayName)
          (builtins.attrValues interfaces);
    in
    builtins.concatLists (map dynamicFirewallCidrsForPeerInterface matchingInterfaces);

  dynamicFirewallCidrsForSiteNode =
    peerSiteCpm: nodeName:
    lib.unique (
      builtins.concatLists (
        map (targetName: targetDynamicFirewallCidrsIn peerSiteCpm nodeName peerSiteCpm.runtimeTargets.${targetName})
          (sortedAttrNames (attrsOrEmpty (peerSiteCpm.runtimeTargets or null)))
      )
    );

  # CPM emits route/prefix `family` as an integer (4/6) for overlay routes and
  # as a string ("ipv4"/"ipv6") for delegated-public-egress prefixes; both are
  # valid canonical forms, so normalize before matching.  A route that cannot be
  # given a `via` is not a usable nebula unsafe route: emitting it with
  # install:true and no via makes nebula refuse to start (FS-460 fail-closed),
  # so fail here instead of producing an invalid entry.
  normalizeFamily =
    family:
    if family == 4 || family == "ipv4" then
      "ipv4"
    else if family == 6 || family == "ipv6" then
      "ipv6"
    else
      throw "FS-460-HDS-010-SDS-010-SMS-030: dynamic unsafe route family must be 4/6 or 'ipv4'/'ipv6', got ${builtins.toJSON family}";

  routeForCidr =
    peer: cidr:
    let
      family = normalizeFamily (cidr.family or null);
      # Peer overlay next hop, in preference order: the peer's modeled overlay
      # participant address on this overlay's provider block (available even
      # when the peer site is not compiled here), then the compiled peer node
      # address.  This is the modeled "endpoint identity" the URS requires.
      via =
        let
          modeled = peerViaFor family;
        in
        if builtins.isString modeled then
          modeled
        else if family == "ipv6" then
          peer.addr6 or null
        else
          peer.addr4 or null;
      missingVia =
        "FS-460-HDS-010-SDS-010-SMS-030: "
        + family
        + " dynamic unsafe route for "
        + builtins.toJSON cidr.sourceFile
        + " has no peer "
        + family
        + " overlay address (nebula.lighthouse.addr4/6) to use as its via";
      viaField =
        if family == "ipv6" then
          { via6 = stripPrefixLength via; }
        else
          { via4 = stripPrefixLength via; };
    in
    if !(builtins.isString via) then
      throw missingVia
    else
      {
        sourceFile = cidr.sourceFile;
        family = cidr.family or null;
      }
      // viaField;

  dynamicUnsafeRoutesForPeerSite =
    nodeName: peerSite:
    let
      peerSiteCpm = peerSiteCpmFor peerSite;
      peerOverlay = attrsOrEmpty (((peerSiteCpm.overlays or { }).${overlayName} or null));
    in
    builtins.concatLists (
      map
        (
          peerNodeName:
          let
            peer = attrsOrEmpty ((peerOverlay.nodes or { }).${peerNodeName} or null);
            cidrs = dynamicFirewallCidrsForSiteNode peerSiteCpm peerNodeName;
          in
          if peerNodeName == nodeName then [ ] else map (routeForCidr peer) cidrs
        )
        (sortedAttrNames (attrsOrEmpty (peerOverlay.nodes or null)))
    );

  peerSites = [ "${siteCpm.enterprise}.${siteCpm.siteName}" ] ++ listOrEmpty (overlayCpm.peerSites or null);
in
nodeName:
lib.unique (builtins.concatLists (map (dynamicUnsafeRoutesForPeerSite nodeName) peerSites))
