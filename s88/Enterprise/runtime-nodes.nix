{ lib
, helpers
, enterpriseName
, siteName
, overlayName
, overlayId
, overlayNodes
, runtimeNodes
, nebulaRuntimeNodes
, localFirewallCidrs
, prefixLength4
, prefixLength6
, lighthousePlan
, }:

let
  inherit (helpers)
    requireAttr
    requireString
    sortedAttrNames
    stripPrefixLength
    uniqueStrings
    withPrefixLength
    ;

  unsafeRouteHelpers = import ./unsafe-routes.nix { inherit lib helpers; };
  inherit (unsafeRouteHelpers) normalizeUnsafeRoutes;
in
builtins.listToAttrs (
  map
    (
      nodeName:
      let
        runtimePath =
          "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.runtimeNodes.${nodeName}";
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
        unsafeRouteInput = nebulaRuntimeNode.unsafeRoutes or null;
        dynamicFirewallCidrsInput = nebulaRuntimeNode.dynamicFirewallCidrs or null;
        dynamicUnsafeRoutesInput = nebulaRuntimeNode.dynamicUnsafeRoutes or null;
        unsafeRoutes =
          if unsafeRouteInput == null then
            [ ]
          else if builtins.isList unsafeRouteInput then
            normalizeUnsafeRoutes unsafeRouteInput
          else
            throw "${nebulaRuntimePath}.unsafeRoutes must be an explicit list";
        dynamicFirewallCidrs =
          if dynamicFirewallCidrsInput == null then
            [ ]
          else if builtins.isList dynamicFirewallCidrsInput then
            lib.unique dynamicFirewallCidrsInput
          else
            throw "${nebulaRuntimePath}.dynamicFirewallCidrs must be an explicit list";
        dynamicUnsafeRoutes =
          if dynamicUnsafeRoutesInput == null then
            [ ]
          else if builtins.isList dynamicUnsafeRoutesInput then
            lib.unique dynamicUnsafeRoutesInput
          else
            throw "${nebulaRuntimePath}.dynamicUnsafeRoutes must be an explicit list";
        unsafeRouteToNebula = route:
          let
            via = route.via6 or route.via4 or route.via or null;
            mtu = route.mtu or (if (route.via6 or null) != null then 1280 else 1200);  # FIXME: CPM must provide explicit mtu per route
          in
          {
            route = route.route;
            inherit mtu;
            install = route.install or true;
          }
          // lib.optionalAttrs (via != null) {
            inherit via;
          };
        unsafeFirewallRules = map
          (route: {
            port = "any";  # FIXME: CPM must provide traffic class scoped port
            proto = "any"; # FIXME: CPM must provide traffic class scoped proto
            host = "any";
            local_cidr = route.route;
          })
          unsafeRoutes;
        baseFirewallRules = map
          (localCidr: {
            port = "any";  # FIXME: CPM must provide traffic class scoped port
            proto = "any"; # FIXME: CPM must provide traffic class scoped proto
            host = "any";
            local_cidr = localCidr;
          })
          (
            localFirewallCidrs
            ++ [
              (withPrefixLength (requireString "${renderedPath}.addr4" (renderedNode.addr4 or null)) 32)
              (withPrefixLength (requireString "${renderedPath}.addr6" (renderedNode.addr6 or null)) 128)
            ]
          );
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
        relay = nebulaRuntimeNode.relay or runtimeNode.relay or { };
        lighthouseStaticHostMap =
          if lighthousePlan.node == nodeName then
            { }
          else
            builtins.listToAttrs (
              map
                (overlayIp: {
                  name = overlayIp;
                  value = lighthousePlan.endpoints;
                })
                lighthousePlan.overlayIps
            );
        lighthouseStaticHostMapSecretEndpoints =
          let
	            dynamicEndpointSpecs =
	              lib.filter (spec: builtins.isString (spec.sourceFile or null) && spec.sourceFile != "") [
	                { sourceFile = lighthousePlan.endpointSourceFile or null; port = lighthousePlan.port; }
	                { sourceFile = lighthousePlan.endpoint6SourceFile or null; port = lighthousePlan.port; }
	              ];
          in
          if lighthousePlan.node == nodeName || dynamicEndpointSpecs == [ ] then
            { }
          else
            builtins.listToAttrs (
              map
                (overlayIp: {
                  name = overlayIp;
                  value = dynamicEndpointSpecs;
                })
                lighthousePlan.overlayIps
            );
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
            dynamicFirewallCidrs
            dynamicUnsafeRoutes
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
            name = runtimeNode.service.name or (throw "FS-310-HDS-010-SDS-010-SMS-110: service.name required by CPM provider contract, cannot default to nebula-runtime");
            interface = runtimeNode.service.interface or (throw "network-renderer-nebula: runtime node ${nodeName} missing service.interface from CPM");
          };
          materialization = builtins.removeAttrs runtimeNode [
            "groups"
            "host"
            "relay"
            "unsafeRoutes"
            "service"
          ];
          inherit relay;
          staticHostMap = (runtimeNode.staticHostMap or { }) // lighthouseStaticHostMap;
          staticHostMapSecretEndpoints =
            (runtimeNode.staticHostMapSecretEndpoints or { }) // lighthouseStaticHostMapSecretEndpoints;
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
    )
    (sortedAttrNames runtimeNodes)
)
