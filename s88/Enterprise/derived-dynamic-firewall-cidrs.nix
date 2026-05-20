{ lib, siteCpm, overlayName }:

let
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];

  localRuntimeRoutedPrefixes =
    lib.concatMap
      (tenant:
        lib.filter
          (prefix:
            (prefix.allocation or "runtime") == "runtime"
            && builtins.isString (prefix.sourceFile or null)
            && prefix.sourceFile != "")
          (listOrEmpty (tenant.routedPrefixes or null)))
      (listOrEmpty ((attrsOrEmpty (siteCpm.domains or null)).tenants or null));

  allRoutesFor = iface:
    let
      routes = attrsOrEmpty (iface.routes or null);
    in
    listOrEmpty (routes.ipv4 or null) ++ listOrEmpty (routes.ipv6 or null);

  routeSpec = route: {
    sourceFile = route.sourceFile;
    family = route.family or 6;
  };

  prefixSpec = prefix: {
    sourceFile = prefix.sourceFile;
    family = prefix.family or 6;
  };
in
iface:
let
  allRoutes = allRoutesFor iface;
  overlayRoute = route: (route.proto or null) == "overlay" && (route.overlay or null) == overlayName;
in
(map routeSpec (
  lib.filter
    (route:
      overlayRoute route
      && !builtins.isString (route.dst or null)
      && builtins.isString (route.sourceFile or null)
      && route.sourceFile != "")
    allRoutes
))
++ (
  if builtins.any (route: overlayRoute route && ((route.intent or { }).kind or null) == "delegated-public-egress") allRoutes then
    map prefixSpec localRuntimeRoutedPrefixes
  else
    [ ]
)
