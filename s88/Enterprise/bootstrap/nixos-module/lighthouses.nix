{ lib
, nebulaRuntimePlan
, runtimeNodeNames
, runtimeNodes
, sanitizeName
, sortedAttrNames
,
}:
let
  overlayNames = sortedAttrNames (nebulaRuntimePlan.overlays or { });

  lighthouseFingerprint = overlayId:
    let
      overlay = nebulaRuntimePlan.overlays.${overlayId};
      lighthouse = overlay.lighthouse or { };
      overlayAddresses = lighthouse.overlayAddresses or [ ];
    in
    lib.concatStringsSep "|" [
      (builtins.elemAt overlayAddresses 0)
      (builtins.elemAt overlayAddresses 1)
      (toString (lighthouse.endpoint or null))
      (toString (lighthouse.endpoint6 or null))
      (builtins.toString (lighthouse.port or (throw "FS-310-HDS-010-SDS-010-SMS-110: lighthouse.port required by CPM provider contract, cannot default to 4242")))
    ];

  lighthouseFingerprints = lib.unique (map lighthouseFingerprint overlayNames);

  matchingOverlaysFor = fingerprint:
    lib.filter (overlayId: fingerprint == lighthouseFingerprint overlayId) overlayNames;

  memberNodesFor = matchingOverlayIds:
    lib.filter
      (nodeName: builtins.elem (runtimeNodes.${nodeName}.overlayId or null) matchingOverlayIds)
      runtimeNodeNames;

  unsafeNetworksFor = memberNodeNames:
    lib.unique (
      builtins.concatLists (
        map (nodeName: map (route: route.route or (throw "FS-310-HDS-010-SDS-010-SMS-110: route.route is required by CPM contract, cannot default to empty string")) (runtimeNodes.${nodeName}.unsafeRoutes or [ ])) memberNodeNames
      )
    );

  lighthouseFor = index: fingerprint:
    let
      matchingOverlayIds = matchingOverlaysFor fingerprint;
      baseOverlay = nebulaRuntimePlan.overlays.${builtins.head matchingOverlayIds};
      baseLighthouse = baseOverlay.lighthouse or { };
      overlayAddresses = baseLighthouse.overlayAddresses or [ ];
      overlayIps = baseLighthouse.overlayIps or [ ];
      memberNodeNames = memberNodesFor matchingOverlayIds;
      unsafeNetworks = unsafeNetworksFor memberNodeNames;
      logicalName = sanitizeName baseOverlay.name;
      name = logicalName;
    in
    {
      inherit name;
      value = {
        id = logicalName;
        overlayIds = matchingOverlayIds;
        node = baseLighthouse.node or null;
        endpoint = baseLighthouse.endpoint or null;
        endpoint6 = baseLighthouse.endpoint6 or null;
        port = builtins.toString (baseLighthouse.port or (throw "FS-310-HDS-010-SDS-010-SMS-110: lighthouse.port required by CPM provider contract, cannot default to 4242"));
        certCidr4 = builtins.elemAt overlayAddresses 0;
        certCidr6 = builtins.elemAt overlayAddresses 1;
        overlayIp4 = builtins.elemAt overlayIps 0;
        overlayIp6 = builtins.elemAt overlayIps 1;
        certNetworks = [
          (builtins.elemAt overlayAddresses 0)
          (builtins.elemAt overlayAddresses 1)
        ];
        unsafeNetworks = unsafeNetworks;
        internal = builtins.isString (baseLighthouse.node or null) && builtins.hasAttr baseLighthouse.node runtimeNodes;
        certBaseName = "${logicalName}-${baseLighthouse.node or (throw "FS-310-HDS-010-SDS-010-SMS-110: lighthouse.node required by CPM provider contract, cannot default to lighthouse")}";
        serviceName = "nebula-lighthouse-${logicalName}";
        interfaceName = "nebula${builtins.toString index}";
        overlayNetworks4Csv = builtins.elemAt overlayAddresses 0;
        overlayNetworks6Csv = builtins.elemAt overlayAddresses 1;
      };
    };
in
builtins.listToAttrs (lib.imap0 lighthouseFor lighthouseFingerprints)
