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

  routeContext = route: "overlay '${overlayName}' route '${route.dst or "<missing-dst>"}'";

  requireRoutePeerSite = route:
    if builtins.isString (route.peerSite or null) && route.peerSite != "" then
      route.peerSite
    else
      throw "network-renderer-nebula: ${routeContext route} must carry concrete peerSite metadata";

  routeIntentKind = route:
    if builtins.isAttrs (route.intent or null) then route.intent.kind or null else null;

  isDefaultRoute = route:
    (route.dst or null) == "0.0.0.0/0" || (route.dst or null) == "::/0";

  validateDefaultRoute = route:
    if isDefaultRoute route && routeIntentKind route != "delegated-public-egress"
    then throw "network-renderer-nebula: ${routeContext route} is a default route but is not delegated-public-egress"
    else route;

  viaForRoute = route:
    let
      peerSite = requireRoutePeerSite route;
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
    {
      route = route.dst;
      install = if (route.policyOnly or false) || isDefaultRoute route then false else route.install or true;
    }
    // viaForRoute route
    // lib.optionalAttrs (builtins.isString (route.routeSourceFile or null)) {
      inherit (route) routeSourceFile;
    };

  splitDefault = route:
    let
      validatedRoute = validateDefaultRoute route;
    in
    if (validatedRoute.family or null) == 4 && (validatedRoute.dst or null) == "0.0.0.0/0" then
      [
        (baseUnsafeRoute (validatedRoute // { dst = "0.0.0.0/1"; install = false; }))
        (baseUnsafeRoute (validatedRoute // { dst = "128.0.0.0/1"; install = false; }))
      ]
    else if (validatedRoute.family or null) == 6 && (validatedRoute.dst or null) == "::/0" then
      [
        (baseUnsafeRoute (validatedRoute // { dst = "::/1"; install = false; }))
        (baseUnsafeRoute (validatedRoute // { dst = "8000::/1"; install = false; }))
      ]
    else
      [ (baseUnsafeRoute validatedRoute) ];

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
