{
  lib,
  helpers,
  caName,
  hostUplinkBridgeNames,
  entry,
}:

let
  inherit (helpers)
    readPrefixLength
    requireAttr
    requireString
    sortedAttrNames
    stripPrefixLength
    uniqueStrings
    withPrefixLength
    ;

  inherit (entry)
    enterpriseName
    siteName
    overlayName
    overlayInventory
    overlayCpm
    ;

  overlayId = "${enterpriseName}::${siteName}::${overlayName}";
  basePath = "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}";
  overlayNodes = requireAttr "${basePath}.nodes" (overlayCpm.nodes or null);
  nebula = requireAttr "${basePath}.nebula" (overlayCpm.nebula or null);
  lighthouse = requireAttr "${basePath}.nebula.lighthouse" (nebula.lighthouse or null);
  lighthouseNodeName = requireString "${basePath}.nebula.lighthouse.node" (lighthouse.node or null);
  lighthouseNode = requireAttr "${basePath}.nodes.${lighthouseNodeName}" (overlayNodes.${lighthouseNodeName} or null);
  ipam = requireAttr "${basePath}.ipam" (overlayCpm.ipam or null);
  ipam4 = requireAttr "${basePath}.ipam.ipv4" (ipam.ipv4 or null);
  ipam6 = requireAttr "${basePath}.ipam.ipv6" (ipam.ipv6 or null);
  prefixLength4 = readPrefixLength (requireString "${basePath}.ipam.ipv4.prefix" (ipam4.prefix or null));
  prefixLength6 = readPrefixLength (requireString "${basePath}.ipam.ipv6.prefix" (ipam6.prefix or null));
  runtimeNodes = overlayInventory.runtimeNodes or { };

  endpoint = requireString "${basePath}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null);
  endpoint6 = requireString "${basePath}.nebula.lighthouse.endpoint6" (lighthouse.endpoint6 or null);
  port = builtins.toString (lighthouse.port or 4242);
  lighthouseAddr4 = requireString "${basePath}.nodes.${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null);
  lighthouseAddr6 = requireString "${basePath}.nodes.${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null);

  lighthousePlan = {
    node = lighthouseNodeName;
    inherit endpoint endpoint6 port;
    endpoints = [
      "${endpoint}:${port}"
      "[${endpoint6}]:${port}"
    ];
    overlayAddresses = [
      (withPrefixLength lighthouseAddr4 prefixLength4)
      (withPrefixLength lighthouseAddr6 prefixLength6)
    ];
    overlayIps = [
      (stripPrefixLength lighthouseAddr4)
      (stripPrefixLength lighthouseAddr6)
    ];
  };

  validateMaterialization =
    path: runtimeNode:
    let
      materialization = builtins.removeAttrs runtimeNode [
        "groups"
        "unsafeRoutes"
        "service"
      ];
      hostBridge = (materialization.container or { }).hostBridge or null;
    in
    if builtins.isString hostBridge && builtins.elem hostBridge hostUplinkBridgeNames then
      throw ''
        network-renderer-nebula: ${path}.container.hostBridge must not attach a Nebula runtime node directly to deployment host uplink bridge '${hostBridge}'

        Use a tenant/access bridge or an explicit targetContainer so underlay reachability traverses the modeled access, policy, selector, and core path.
      ''
    else
      materialization;
in
{
  name = overlayId;
  value = {
    type = "nebula";
    name = overlayName;
    inherit enterpriseName siteName overlayId;
    ca = { name = caName; };
    lighthouse = lighthousePlan;
    nodes = import ./runtime-nodes.nix {
      inherit
        lib
        helpers
        enterpriseName
        siteName
        overlayName
        overlayId
        overlayNodes
        runtimeNodes
        prefixLength4
        prefixLength6
        lighthousePlan
        validateMaterialization
        ;
    };
  };
}
