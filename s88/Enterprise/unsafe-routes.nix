{ lib, helpers }:

let
  inherit (helpers) sortedAttrNames;

  routeKey =
    route:
    lib.concatStringsSep "|" [
      (route.route or (throw "FS-310-HDS-010-SDS-010-SMS-110: route.route is required by CPM contract, cannot default to empty string"))
      (toString (route.via4 or null))
      (toString (route.via6 or null))
      (toString (route.via or null))
      (toString (route.routeSourceFile or null))
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

  isSplitDefaultRoute = route:
    builtins.elem (route.route or null) [
      "0.0.0.0/1"
      "128.0.0.0/1"
      "::/1"
      "8000::/1"
    ];

  normalizeUnsafeRoute = route:
    if isSplitDefaultRoute route then route // { install = false; } else route;
in
{
  normalizeUnsafeRoutes = routes: uniqueRoutes (map normalizeUnsafeRoute routes);
}
