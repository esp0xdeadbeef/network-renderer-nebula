{ lib
, baseRuntimeNodes
, runtimeNodeNames
, stripPrefixLength
,
}:

let
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
        lib.filter
          (
            route:
            (route.via4 or null) == overlayIp4
            || (route.via6 or null) == overlayIp6
          )
          allRoutes;
    in
    lib.unique (map (route: route.route or (throw "FS-310-HDS-010-SDS-010-SMS-110: route.route is required by CPM contract, cannot default to empty string")) advertisedRoutes);

  advertisedUnsafeNetworkSourceFilesFor =
    nodeName:
    lib.unique (
      map (cidr: cidr.sourceFile) (
        lib.filter
          (cidr: builtins.isString (cidr.sourceFile or null) && cidr.sourceFile != "")
          (baseRuntimeNodes.${nodeName}.dynamicFirewallCidrs or [ ])
      )
    );
in
nodeName: {
  advertisedUnsafeNetworks = advertisedUnsafeNetworksFor nodeName;
  advertisedUnsafeNetworkSourceFiles = advertisedUnsafeNetworkSourceFilesFor nodeName;
}
