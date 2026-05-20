{
  lib,
  helpers,
  cpmData,
  siteCpm,
  overlayName,
  overlayCpm,
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

  routeForCidr =
    peer: cidr:
    {
      sourceFile = cidr.sourceFile;
      family = cidr.family or null;
    }
    // lib.optionalAttrs ((cidr.family or null) == "ipv6" && builtins.isString (peer.addr6 or null)) {
      via6 = stripPrefixLength peer.addr6;
    }
    // lib.optionalAttrs ((cidr.family or null) == "ipv4" && builtins.isString (peer.addr4 or null)) {
      via4 = stripPrefixLength peer.addr4;
    };

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
