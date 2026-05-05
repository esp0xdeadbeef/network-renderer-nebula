{
  lib,
  nebulaRuntimePlan ? {
    overlays = { };
    nodes = { };
  },
  externalLighthouseReturnIpv4Cidrs ? [ ],
  externalLighthousePublicIpv4SecretPath ? null,
  externalLighthousePublicIpv6SecretPath ? null,
  externalLighthouseSshHostSecretPath ? externalLighthousePublicIpv4SecretPath,
  externalPortForwardPublicIpv4SecretPath ? externalLighthousePublicIpv4SecretPath,
  externalPortForwardPublicIpv6SecretPath ? externalLighthousePublicIpv6SecretPath,
  externalPortForwardNodeNames ? [ ],
  externalRuntimeNodeNames ? externalPortForwardNodeNames,
  runtimeListenHosts ? { },
  externalRemoteLighthouseEndpoint4 ? null,
  externalRemoteLighthouseEndpoint6 ? null,
  externalSuppressPublicLighthouseStaticMap ? false,
}:
let
  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizeName =
    value:
    lib.replaceStrings
      [
        "::"
        ":"
        "."
        "/"
        " "
      ]
      [
        "-"
        "-"
        "-"
        "-"
        "-"
      ]
      value;

  runtimeNodeNames = sortedAttrNames (nebulaRuntimePlan.nodes or { });

  stripPrefixLength = value: builtins.head (lib.splitString "/" value);

  runtimeListenHostFor = nodeName:
    let
      value = runtimeListenHosts.${nodeName} or null;
    in
    if value == null then
      null
    else if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nebula: runtimeListenHosts.${nodeName} must be a non-empty string";

  baseRuntimeNodes =
    builtins.mapAttrs (
      nodeName: node:
      let
        overlayAddresses = node.overlayAddresses or [ ];
        lighthouse = node.lighthouse or { };
        lighthouseAddresses = lighthouse.overlayAddresses or [ ];
        lighthouseIps = lighthouse.overlayIps or [ ];
        isLighthouse = (lighthouse.node or null) == nodeName;
        groups = lib.unique ((node.groups or [ ]) ++ lib.optional isLighthouse "lighthouse");
      in
      {
        overlayId = node.overlayId or null;
        inherit isLighthouse;
        certCidr4 = builtins.elemAt overlayAddresses 0;
        certCidr6 = builtins.elemAt overlayAddresses 1;
        groupsCsv = lib.concatStringsSep "," groups;
        unsafeRoutes = node.unsafeRoutes or [ ];
        routePreparation = node.routePreparation or { };
        service = node.service or {
          name = "nebula-runtime";
          interface = "nebula1";
        } // lib.optionalAttrs (runtimeListenHostFor nodeName != null) {
          listenHost = runtimeListenHostFor nodeName;
        };
        materialization = node.materialization or { };
        lighthouse = {
          overlayId = node.overlayId or null;
          node = lighthouse.node or null;
          endpoint = lighthouse.endpoint or null;
          endpoint6 = lighthouse.endpoint6 or null;
          port = builtins.toString (lighthouse.port or 4242);
          certCidr4 = builtins.elemAt lighthouseAddresses 0;
          certCidr6 = builtins.elemAt lighthouseAddresses 1;
          overlayIp4 = builtins.elemAt lighthouseIps 0;
          overlayIp6 = builtins.elemAt lighthouseIps 1;
        };
      }
    ) (nebulaRuntimePlan.nodes or { });

  advertisedUnsafeNetworksFor =
    nodeName:
    let
      node = baseRuntimeNodes.${nodeName};
      overlayIp4 = stripPrefixLength node.certCidr4;
      overlayIp6 = stripPrefixLength node.certCidr6;
      allRoutes = builtins.concatLists (
        map (name: baseRuntimeNodes.${name}.unsafeRoutes or [ ]) runtimeNodeNames
      );
      advertisedRoutes =
        lib.filter (
          route:
          (route.via4 or null) == overlayIp4
          || (route.via6 or null) == overlayIp6
        ) allRoutes;
    in
    lib.unique (map (route: route.route or "") advertisedRoutes);

  runtimeNodes =
    builtins.mapAttrs (
      nodeName: node:
      node
      // {
        advertisedUnsafeNetworks = advertisedUnsafeNetworksFor nodeName;
      }
    ) baseRuntimeNodes;

  lighthouses = import ./lighthouses.nix {
    inherit
      lib
      nebulaRuntimePlan
      runtimeNodeNames
      runtimeNodes
      sanitizeName
      sortedAttrNames
      ;
  };

  runtimeNodesJson = builtins.toJSON runtimeNodes;
  lighthousesJson = builtins.toJSON lighthouses;
  externalPortForwardNodeNamesJson = builtins.toJSON externalPortForwardNodeNames;
  externalRuntimeNodeNamesJson = builtins.toJSON externalRuntimeNodeNames;
  externalLighthouseReturnIpv4CidrsCsv = lib.concatStringsSep "," externalLighthouseReturnIpv4Cidrs;
  shellArgOrEmpty = value: lib.escapeShellArg (if value == null then "" else value);
  externalLighthousePublicIpv4SecretPathArg = shellArgOrEmpty externalLighthousePublicIpv4SecretPath;
  externalLighthousePublicIpv6SecretPathArg = shellArgOrEmpty externalLighthousePublicIpv6SecretPath;
  externalLighthouseSshHostSecretPathArg = shellArgOrEmpty externalLighthouseSshHostSecretPath;
  externalPortForwardPublicIpv4SecretPathArg = shellArgOrEmpty externalPortForwardPublicIpv4SecretPath;
  externalPortForwardPublicIpv6SecretPathArg = shellArgOrEmpty externalPortForwardPublicIpv6SecretPath;
  externalRemoteLighthouseEndpoint4Arg = shellArgOrEmpty externalRemoteLighthouseEndpoint4;
  externalRemoteLighthouseEndpoint6Arg = shellArgOrEmpty externalRemoteLighthouseEndpoint6;
  externalSuppressPublicLighthouseStaticMapArg =
    if externalSuppressPublicLighthouseStaticMap then "1" else "0";
in
{
  inherit
    externalLighthousePublicIpv4SecretPathArg
    externalLighthousePublicIpv6SecretPathArg
    externalLighthouseReturnIpv4CidrsCsv
    externalLighthouseSshHostSecretPathArg
    externalPortForwardNodeNamesJson
    externalPortForwardPublicIpv4SecretPathArg
    externalPortForwardPublicIpv6SecretPathArg
    externalRuntimeNodeNamesJson
    externalRemoteLighthouseEndpoint4Arg
    externalRemoteLighthouseEndpoint6Arg
    externalSuppressPublicLighthouseStaticMapArg
    lighthouses
    lighthousesJson
    runtimeNodeNames
    runtimeNodes
    runtimeNodesJson
    ;
}
