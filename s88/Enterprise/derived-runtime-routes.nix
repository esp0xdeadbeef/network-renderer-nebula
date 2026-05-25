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
  overlayPeerSites = listOrEmpty (overlayCpm.peerSites or null);
  firstPeerSite = if overlayPeerSites == [ ] then null else builtins.head overlayPeerSites;
  dynamicFirewallCidrsForInterface = import ./derived-dynamic-firewall-cidrs.nix {
    inherit lib overlayName;
    inherit siteCpm;
  };
  dynamicUnsafeRoutesForNode = import ./derived-dynamic-unsafe-routes.nix {
    inherit
      lib
      helpers
      cpmData
      siteCpm
      overlayName
      overlayCpm
      ;
  };

  routeKey =
    route:
    lib.concatStringsSep "|" [
      (route.route or "")
      (route.via4 or "")
      (route.via6 or "")
      (route.routeSourceFile or "")
      (if route.install or true then "install" else "noinstall")
    ];

  uniqueRoutes =
    routes:
    let
      keyed = builtins.listToAttrs (
        map
          (route: {
            name = routeKey route;
            value = route;
          })
          routes
      );
    in
    map (key: keyed.${key}) (sortedAttrNames keyed);

  siteForPeer = peerSite:
    let
      parts = lib.splitString "." peerSite;
    in
    if builtins.length parts != 2 then
      null
    else
      let
        enterpriseName = builtins.elemAt parts 0;
        siteName = builtins.elemAt parts 1;
      in
        (((cpmData.${enterpriseName} or { }).${siteName} or { }).overlays or { }).${overlayName} or null;

  viaForRoute = route:
    let
      routePeerSite = route.peerSite or null;
      peerSite = if builtins.isString routePeerSite then routePeerSite else firstPeerSite;
      peerOverlay = if builtins.isString peerSite then siteForPeer peerSite else null;
      terminateOn = if builtins.isAttrs peerOverlay then listOrEmpty (peerOverlay.terminateOn or null) else [ ];
      peerNodeName = if terminateOn == [ ] then null else builtins.head terminateOn;
      peerNode = if builtins.isString peerNodeName then attrsOrEmpty ((peerOverlay.nodes or { }).${peerNodeName} or null) else { };
      family = route.family or null;
    in
    if family == 4 && builtins.isString (peerNode.addr4 or null) then
      { via4 = stripPrefixLength peerNode.addr4; }
    else if family == 6 && builtins.isString (peerNode.addr6 or null) then
      { via6 = stripPrefixLength peerNode.addr6; }
    else
      { };

  baseUnsafeRoute = route:
    let
      isDefaultRoute = (route.dst or null) == "0.0.0.0/0" || (route.dst or null) == "::/0";
    in
    {
      route = route.dst;
      install = if (route.policyOnly or false) || isDefaultRoute then false else route.install or true;
    }
    // viaForRoute route
    // lib.optionalAttrs (builtins.isString (route.routeSourceFile or null)) {
      inherit (route) routeSourceFile;
    };

  splitDefault = route:
    if (route.family or null) == 4 && (route.dst or null) == "0.0.0.0/0" then
      [
        (baseUnsafeRoute (route // { dst = "0.0.0.0/1"; install = false; }))
        (baseUnsafeRoute (route // { dst = "128.0.0.0/1"; install = false; }))
      ]
    else if (route.family or null) == 6 && (route.dst or null) == "::/0" then
      [
        (baseUnsafeRoute (route // { dst = "::/1"; install = false; }))
        (baseUnsafeRoute (route // { dst = "8000::/1"; install = false; }))
      ]
    else
      [ (baseUnsafeRoute route) ];

  overlayRoutesForInterface = iface:
    let
      routes = attrsOrEmpty (iface.routes or null);
      allRoutes = listOrEmpty (routes.ipv4 or null) ++ listOrEmpty (routes.ipv6 or null);
    in
    builtins.concatLists (
      map splitDefault (
        lib.filter
          (route: (route.proto or null) == "overlay" && (route.overlay or null) == overlayName && builtins.isString (route.dst or null))
          allRoutes
      )
    );

  targetOverlayRoutes =
    nodeName: target:
    let
      interfaces = attrsOrEmpty ((target.effectiveRuntimeRealization or { }).interfaces or null);
      matchingInterfaces =
        lib.filter
          (iface: (iface.logicalNode or null) == nodeName && ((iface.backingRef or { }).name or null) == overlayName)
          (builtins.attrValues interfaces);
    in
    builtins.concatLists (map overlayRoutesForInterface matchingInterfaces);

  targetDynamicFirewallCidrs =
    nodeName: target:
    let
      interfaces = attrsOrEmpty ((target.effectiveRuntimeRealization or { }).interfaces or null);
      matchingInterfaces =
        lib.filter
          (iface: (iface.logicalNode or null) == nodeName && ((iface.backingRef or { }).name or null) == overlayName)
          (builtins.attrValues interfaces);
    in
    builtins.concatLists (map dynamicFirewallCidrsForInterface matchingInterfaces);

  routesForNode = nodeName:
    uniqueRoutes (
      builtins.concatLists (
        map (targetName: targetOverlayRoutes nodeName siteCpm.runtimeTargets.${targetName})
          (sortedAttrNames (attrsOrEmpty (siteCpm.runtimeTargets or null)))
      )
    );

  dynamicFirewallCidrsForNode =
    nodeName:
    lib.unique (
      builtins.concatLists (
        map (targetName: targetDynamicFirewallCidrs nodeName siteCpm.runtimeTargets.${targetName})
          (sortedAttrNames (attrsOrEmpty (siteCpm.runtimeTargets or null)))
      )
    );
in
builtins.listToAttrs (
  map
    (nodeName: {
      name = nodeName;
      value = {
        unsafeRoutes = routesForNode nodeName;
        dynamicFirewallCidrs = dynamicFirewallCidrsForNode nodeName;
        dynamicUnsafeRoutes = dynamicUnsafeRoutesForNode nodeName;
      };
    })
    (sortedAttrNames (attrsOrEmpty (overlayCpm.nodes or null)))
)
