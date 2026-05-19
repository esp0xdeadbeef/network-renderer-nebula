{ lib, helpers }:

let
  routeKey =
    route:
    lib.concatStringsSep "|" [
      (route.route or "")
      (route.via4 or "")
      (route.via6 or "")
      (route.via or "")
      (route.routeSourceFile or "")
      (if route.install or true then "install" else "noinstall")
    ];

  uniqueBy =
    keyFor: values:
    let
      keyed = builtins.listToAttrs (
        map (value: {
          name = keyFor value;
          inherit value;
        }) values
      );
    in
    map (key: keyed.${key}) (helpers.sortedAttrNames keyed);

  uniqueRoutes = uniqueBy routeKey;
  uniqueFirewallRules = uniqueBy builtins.toJSON;

  mergeRoutePreparation =
    nodes:
    let
      listsFor = field:
        builtins.concatLists (map (node: (node.routePreparation or { }).${field} or [ ]) nodes);
    in
    {
      removeRoutes = helpers.uniqueStrings (listsFor "removeRoutes");
      overlayHosts = helpers.uniqueStrings (listsFor "overlayHosts");
      underlayEndpoints = helpers.uniqueStrings (listsFor "underlayEndpoints");
    };

  mergeNebulaNetwork =
    nodes:
    let
      tunSettings = map (node: (((node.nebulaNetwork or { }).settings or { }).tun or { })) nodes;
      firewallRules = map (node: (((node.nebulaNetwork or { }).settings or { }).nebulaFirewallRules or { })) nodes;
      baseTun = builtins.foldl' (acc: tun: acc // tun) { } tunSettings;
    in
    {
      settings = {
        nebulaFirewallRules = {
          outbound = uniqueFirewallRules (
            builtins.concatLists (map (rules: rules.outbound or [ ]) firewallRules)
          );
          inbound = uniqueFirewallRules (
            builtins.concatLists (map (rules: rules.inbound or [ ]) firewallRules)
          );
        };
        tun =
          baseTun
          // {
            unsafe_routes = uniqueRoutes (
              builtins.concatLists (map (tun: tun.unsafe_routes or [ ]) tunSettings)
            );
          };
      };
    };
in
{
  mergeRawNodeEntries =
    entries:
    let
      nodeNames = helpers.uniqueStrings (map (entry: entry.name) entries);
      mergeRawNodes =
        nodeName:
        let
          matching = map (entry: entry.value) (lib.filter (entry: entry.name == nodeName) entries);
          base = builtins.head matching;
        in
        base
        // {
          unsafeRoutes = uniqueRoutes (builtins.concatLists (map (node: node.unsafeRoutes or [ ]) matching));
          routePreparation = mergeRoutePreparation matching;
          nebulaNetwork = mergeNebulaNetwork matching;
        };
    in
    builtins.listToAttrs (
      map (nodeName: {
        name = nodeName;
        value = mergeRawNodes nodeName;
      }) nodeNames
    );
}
