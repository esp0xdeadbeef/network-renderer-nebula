{
  lib,
  helpers,
  enterpriseName,
  siteName,
  overlayName,
  overlayId,
  overlayNodes,
  runtimeNodes,
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
in
builtins.listToAttrs (
  map (
    nodeName:
    let
      runtimePath =
        "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.runtimeNodes.${nodeName}";
      runtimeNode = requireAttr runtimePath (runtimeNodes.${nodeName} or null);
      renderedPath =
        "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes.${nodeName}";
      renderedNode = requireAttr renderedPath (overlayNodes.${nodeName} or null);
      unsafeRoutes =
        if builtins.isList (runtimeNode.unsafeRoutes or null) then
          lib.filter builtins.isAttrs runtimeNode.unsafeRoutes
        else
          [ ];
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
    {
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
        materialization = validateMaterialization runtimePath runtimeNode;
        lighthouse = lighthousePlan;
      };
    }
  ) (sortedAttrNames runtimeNodes)
)
