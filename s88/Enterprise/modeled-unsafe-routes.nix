{
  lib,
  helpers,
  overlayName,
  overlayId,
  siteCpm,
  cpmData,
}:

let
  inherit (helpers) sortedAttrNames stripPrefixLength;

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];
  isString = value: builtins.isString value && value != "";
  hasInfix = needle: value: builtins.isString value && lib.hasInfix needle value;

  runtimeTargets = attrsOrEmpty (siteCpm.runtimeTargets or null);

  runtimeTargetForNode =
    nodeName:
    let
      matches = lib.filter (
        targetName:
        let
          target = runtimeTargets.${targetName};
          logical = attrsOrEmpty (target.logicalNode or null);
        in
        (logical.name or null) == nodeName
      ) (sortedAttrNames runtimeTargets);
    in
    if matches == [ ] then
      { }
    else if builtins.length matches == 1 then
      runtimeTargets.${builtins.head matches}
    else
      throw ''
        network-renderer-nebula: multiple runtime targets matched overlay node '${nodeName}'
        matches:
        ${builtins.toJSON matches}
      '';

  splitPeerSite =
    peerSite:
    let
      parts = lib.splitString "." peerSite;
    in
    if builtins.length parts != 2 then null else {
      enterprise = builtins.elemAt parts 0;
      site = builtins.elemAt parts 1;
    };

  peerOverlayGatewayFor =
    family: peerSite:
    let
      peer = splitPeerSite peerSite;
      peerOverlay =
        if
          peer == null
          || !(builtins.hasAttr peer.enterprise cpmData)
          || !(builtins.hasAttr peer.site (attrsOrEmpty cpmData.${peer.enterprise}))
          || !(builtins.hasAttr overlayName (attrsOrEmpty (cpmData.${peer.enterprise}.${peer.site}.overlays or null)))
        then
          null
        else
          cpmData.${peer.enterprise}.${peer.site}.overlays.${overlayName};
      terminators = if peerOverlay == null then [ ] else listOrEmpty (peerOverlay.terminateOn or null);
      terminator =
        if terminators == [ ] then
          null
        else if builtins.length terminators == 1 then
          builtins.head terminators
        else
          throw ''
            network-renderer-nebula: overlay '${overlayId}' peer site '${peerSite}' has multiple terminators
            terminateOn:
            ${builtins.toJSON terminators}
          '';
      peerNodes = if peerOverlay == null then { } else attrsOrEmpty (peerOverlay.nodes or null);
      gatewayCidr =
        if terminator == null || !(builtins.hasAttr terminator peerNodes) then
          null
        else if family == 6 then
          peerNodes.${terminator}.addr6 or null
        else
          peerNodes.${terminator}.addr4 or null;
    in
    if gatewayCidr == null then null else stripPrefixLength gatewayCidr;

  routeValues =
    routes:
    if builtins.isList routes then
      routes
    else if builtins.isAttrs routes then
      (listOrEmpty (routes.ipv4 or null)) ++ (listOrEmpty (routes.ipv6 or null))
    else
      [ ];

  overlayRoutesForNode =
    nodeName:
    let
      target = runtimeTargetForNode nodeName;
      interfaces = attrsOrEmpty ((target.effectiveRuntimeRealization or { }).interfaces or null);
      overlayInterfaces = lib.filter (
        ifName:
        let
          iface = interfaces.${ifName};
        in
        (iface.sourceKind or null) == "overlay"
        && ((iface.backingRef or { }).name or null) == overlayName
      ) (sortedAttrNames interfaces);
      routes = builtins.concatLists (
        map (ifName: routeValues (interfaces.${ifName}.routes or null)) overlayInterfaces
      );
    in
    lib.filter (
      route:
      builtins.isAttrs route
      && isString (route.dst or null)
      && (route.proto or null) == "overlay"
      && (route.overlay or null) == overlayName
    ) routes;

  modeledUnsafeRoutesForNode =
    nodeName:
    map (
      route:
      let
        family = if hasInfix ":" route.dst then 6 else 4;
        gateway = peerOverlayGatewayFor family (route.peerSite or "");
      in
      if gateway == null then
        throw ''
          network-renderer-nebula: overlay route for '${nodeName}' on '${overlayId}' is missing a resolvable peer gateway
          route:
          ${builtins.toJSON route}
        ''
      else
        {
          route = route.dst;
          install = true;
        }
        // (if family == 6 then { via6 = gateway; } else { via4 = gateway; })
    ) (overlayRoutesForNode nodeName);
in
{
  inherit modeledUnsafeRoutesForNode;
}
