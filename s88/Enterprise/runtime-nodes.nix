{
  lib,
  helpers,
  enterpriseName,
  siteName,
  overlayName,
  overlayId,
  overlayNodes,
  runtimeNodes,
  nebulaRuntimeNodes,
  prefixLength4,
  prefixLength6,
  lighthousePlan,
  validateMaterialization,
}:

let
  inherit (helpers)
    requireAttr
    requireString
    sortedAttrNames
    stripPrefixLength
    uniqueStrings
    withPrefixLength
    ;

  uniqueRoutes =
    routes:
    let
      keyed = builtins.listToAttrs (
        map (
          route:
          let
            key = lib.concatStringsSep "|" [
              (route.route or "")
              (route.via4 or "")
              (route.via6 or "")
              (route.routeSourceFile or "")
              (if route.install or true then "install" else "noinstall")
            ];
          in
          {
            name = key;
            value = route;
          }
        ) routes
      );
    in
    map (key: keyed.${key}) (sortedAttrNames keyed);
in
builtins.listToAttrs (
  map (
    nodeName:
    let
      runtimePath =
        "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.runtimeNodes.${nodeName}";
      runtimeNode = requireAttr runtimePath (runtimeNodes.${nodeName} or null);
      nebulaRuntimePath =
        "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nebula.runtimeNodes.${nodeName}";
      nebulaRuntimeNode = requireAttr nebulaRuntimePath (nebulaRuntimeNodes.${nodeName} or null);
      renderedPath =
        "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes.${nodeName}";
      renderedNode = requireAttr renderedPath (overlayNodes.${nodeName} or null);
      _noInventoryUnsafeRoutes =
        if runtimeNode ? unsafeRoutes then
          throw "${runtimePath}.unsafeRoutes is policy; CPM must provide overlay route contracts"
        else
          true;
      unsafeRoutes =
        if builtins.isList (nebulaRuntimeNode.unsafeRoutes or null) then
          uniqueRoutes nebulaRuntimeNode.unsafeRoutes
        else
          throw "${nebulaRuntimePath}.unsafeRoutes must be an explicit list";
      unsafeRouteToNebula = route:
        let
          via = route.via6 or route.via4 or route.via or null;
          mtu = if (route.via6 or null) != null then 1280 else 1200;
        in
        {
          route = route.route;
          inherit mtu;
          install = route.install or true;
        }
        // lib.optionalAttrs (via != null) {
          inherit via;
        };
      unsafeFirewallRules = map (route: {
        port = "any";
        proto = "any";
        host = "any";
        local_cidr = route.route;
      }) unsafeRoutes;
      baseFirewallRules = [
        {
          port = "any";
          proto = "any";
          host = "any";
        }
      ];
      routePreparation = {
        removeRoutes = uniqueStrings (
          map (route: route.route or null) (lib.filter (route: (route.install or true)) unsafeRoutes)
        );
        overlayHosts = uniqueStrings (map stripPrefixLength lighthousePlan.overlayAddresses);
        underlayEndpoints = uniqueStrings [
          lighthousePlan.endpoint
          lighthousePlan.endpoint6
        ];
      };
    in
    builtins.seq _noInventoryUnsafeRoutes {
      name = nodeName;
      value = {
        inherit
          enterpriseName
          siteName
          overlayName
          overlayId
          unsafeRoutes
          routePreparation
          ;
        overlayAddresses = [
          (withPrefixLength (requireString "${renderedPath}.addr4" (renderedNode.addr4 or null)) prefixLength4)
          (withPrefixLength (requireString "${renderedPath}.addr6" (renderedNode.addr6 or null)) prefixLength6)
        ];
        groups =
          if builtins.isList (runtimeNode.groups or null) then
            lib.filter builtins.isString runtimeNode.groups
          else
            [ ];
        service = (runtimeNode.service or { }) // {
          name = runtimeNode.service.name or "nebula-runtime";
          interface = runtimeNode.service.interface or "nebula1";
        };
        materialization = validateMaterialization nodeName runtimePath runtimeNode;
        relay = nebulaRuntimeNode.relay or runtimeNode.relay or { };
        lighthouse = lighthousePlan;
        nebulaNetwork = {
          settings = {
            nebulaFirewallRules = {
              outbound = baseFirewallRules ++ unsafeFirewallRules;
              inbound = baseFirewallRules ++ unsafeFirewallRules;
            };
            tun = lib.optionalAttrs (unsafeRoutes != [ ]) {
              unsafe_routes = map unsafeRouteToNebula unsafeRoutes;
            };
          };
        };
      };
    }
  ) (sortedAttrNames runtimeNodes)
)
