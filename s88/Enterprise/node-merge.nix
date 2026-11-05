{ lib, helpers }:

let
  routeKey =
    route:
    lib.concatStringsSep "|" [
      (route.route or (throw "FS-310-HDS-010-SDS-010-SMS-110: route.route is required by CPM contract, cannot default to empty string"))
      (toString (route.via4 or null))
      (toString (route.via6 or null))
      (toString (route.via or null))
      (toString (route.routeSourceFile or null))
      (if route.install or false then "install" else "noinstall")
    ];

  uniqueBy =
    keyFor: values:
    let
      keyed = builtins.listToAttrs (
        map
          (value: {
            name = keyFor value;
            inherit value;
          })
          values
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

  dynamicFirewallCidrKey =
    spec:
    lib.concatStringsSep "|" [
      (toString (spec.sourceFile or null))
      (toString (spec.family or null))
    ];

  # FS-171 ("A consumer imports, it does not re-derive") and FS-310 ("If
  # required policy input is missing or ambiguous, the renderer shall report the
  # limitation or failure instead of repairing the model"): the same node can be
  # present in more than one site's overlay instance, and each instance declares
  # the target facts it carries.  Filling a fact from another instance is
  # importing it; dropping it because an earlier instance omits it deletes
  # modeled facts.  Two instances declaring the same key with different values
  # is an ambiguous model and fails closed here instead of picking one.
  mergeDeclaredFacts =
    { nodeName, field, path }:
    values:
    let
      declared = builtins.filter (value: value != null) values;
    in
    if declared == [ ] then
      null
    else if builtins.all builtins.isAttrs declared then
      builtins.listToAttrs
        (
          map
            (key: {
              name = key;
              value = mergeDeclaredFacts
                {
                  inherit nodeName field;
                  path = "${path}.${key}";
                }
                (map (value: value.${key} or null) declared);
            })
            (helpers.uniqueStrings (builtins.concatMap builtins.attrNames declared))
        )
    else
      let
        first = builtins.head declared;
      in
      if builtins.all (value: value == first) declared then
        first
      else
        throw "FS-310: node '${nodeName}' ${field} is declared with conflicting values at ${path}: ${builtins.toJSON declared}; the renderer shall report the ambiguity instead of repairing the model";

  firewallRulesForNetworks =
    networks:
    map
      (localCidr: {
        port = "any";
        proto = "any";
        host = "any";
        local_cidr = localCidr;
      })
      networks;
in
{
  mergeRawNodeEntries =
    entries:
    let
      nodeNames = helpers.uniqueStrings (map (entry: entry.name) entries);
      stripPrefixLength = value: builtins.head (lib.splitString "/" value);
      mergeRawNodes =
        nodeName:
        let
          matching = map (entry: entry.value) (lib.filter (entry: entry.name == nodeName) entries);
          base = builtins.head matching;
          overlayAddresses = base.overlayAddresses or [ ];
          overlayIp4 = if builtins.length overlayAddresses > 0 then stripPrefixLength (builtins.elemAt overlayAddresses 0) else null;
          overlayIp6 = if builtins.length overlayAddresses > 1 then stripPrefixLength (builtins.elemAt overlayAddresses 1) else null;
          allUnsafeRoutes = builtins.concatLists (map (entry: entry.value.unsafeRoutes or [ ]) entries);
          advertisedUnsafeNetworks =
            helpers.uniqueStrings (
              map (route: route.route or (throw "FS-310-HDS-010-SDS-010-SMS-110: route.route is required by CPM contract, cannot default to empty string"))
                (lib.filter
                  (route:
                    (overlayIp4 != null && (route.via4 or route.via or null) == overlayIp4)
                    || (overlayIp6 != null && (route.via6 or route.via or null) == overlayIp6))
                  allUnsafeRoutes)
            );
          baseNebulaNetwork = mergeNebulaNetwork matching;
          advertisedFirewallRules = firewallRulesForNetworks advertisedUnsafeNetworks;
          dynamicFirewallCidrs =
            uniqueBy dynamicFirewallCidrKey (
              builtins.concatLists (map (node: node.dynamicFirewallCidrs or [ ]) matching)
            );
        in
        base
        // {
          unsafeRoutes = uniqueRoutes (builtins.concatLists (map (node: node.unsafeRoutes or [ ]) matching));
          inherit advertisedUnsafeNetworks;
          inherit dynamicFirewallCidrs;
          materialization =
            let
              merged = mergeDeclaredFacts
                {
                  inherit nodeName;
                  field = "materialization";
                  path = "materialization";
                }
                (map (node: node.materialization or null) matching);
            in
            if merged == null then { } else merged;
          groups = helpers.uniqueStrings (builtins.concatLists (map (node: node.groups or [ ]) matching));
          service =
            let
              merged = mergeDeclaredFacts
                {
                  inherit nodeName;
                  field = "service";
                  path = "service";
                }
                (map (node: node.service or null) matching);
            in
            if merged == null then (base.service or { }) else merged;
          routePreparation = mergeRoutePreparation matching;
          nebulaNetwork =
            baseNebulaNetwork
            // {
              settings =
                baseNebulaNetwork.settings
                // {
                  nebulaFirewallRules = {
                    inbound = uniqueFirewallRules (baseNebulaNetwork.settings.nebulaFirewallRules.inbound ++ advertisedFirewallRules);
                    outbound = uniqueFirewallRules (baseNebulaNetwork.settings.nebulaFirewallRules.outbound ++ advertisedFirewallRules);
                  };
                };
            };
        };
    in
    builtins.listToAttrs (
      map
        (nodeName: {
          name = nodeName;
          value = mergeRawNodes nodeName;
        })
        nodeNames
    );
}
