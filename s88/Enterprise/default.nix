{
  lib,
  system,
  flakeInputs,
}:
let
  cpmLib = flakeInputs.network-control-plane-model.libBySystem.${system};

  requireAttr =
    path: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nebula: missing attrset at ${path}";

  requireString =
    path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nebula: missing string at ${path}";

  stripPrefixLength =
    cidr:
    let
      match = builtins.match "([^/]+)/[0-9]+" cidr;
    in
    if match == null then
      throw "network-renderer-nebula: expected CIDR, got ${builtins.toJSON cidr}"
    else
      builtins.head match;

  readPrefixLength =
    cidr:
    let
      match = builtins.match "[^/]+/([0-9]+)" cidr;
    in
    if match == null then
      throw "network-renderer-nebula: expected CIDR prefix length, got ${builtins.toJSON cidr}"
    else
      builtins.fromJSON (builtins.head match);

  withPrefixLength = cidr: prefixLength: "${stripPrefixLength cidr}/${builtins.toString prefixLength}";
  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
  uniqueStrings = values: lib.unique (lib.filter (value: builtins.isString value && value != "") values);

  collectHostUplinkBridgeNames =
    inventory:
    let
      hosts = (((inventory.deployment or { }).hosts or { }));
    in
    lib.unique (
      builtins.concatLists (
        map (
          hostName:
          let
            host = hosts.${hostName};
            uplinks = host.uplinks or { };
          in
          map (uplinkName: uplinks.${uplinkName}.bridge or null) (sortedAttrNames uplinks)
        ) (sortedAttrNames hosts)
      )
    );

  buildNebulaPlanImpl =
    {
      controlPlane,
      inventory ? { },
      caName ? "s-router-test-lab",
    }:
    let
      cpm =
        if controlPlane ? control_plane_model && builtins.isAttrs controlPlane.control_plane_model then
          controlPlane.control_plane_model
        else
          throw "network-renderer-nebula: controlPlane.control_plane_model is required";

      cpmData = cpm.data or { };
      inventorySites = ((inventory.controlPlane or { }).sites or { });
      hostUplinkBridgeNames = collectHostUplinkBridgeNames inventory;

      validateRuntimeMaterialization =
        path: runtimeNode:
        let
          materialization = builtins.removeAttrs runtimeNode [
            "groups"
            "unsafeRoutes"
            "service"
          ];
          container = materialization.container or { };
          hostBridge = container.hostBridge or null;
        in
        if builtins.isString hostBridge && builtins.elem hostBridge hostUplinkBridgeNames then
          throw ''
            network-renderer-nebula: ${path}.container.hostBridge must not attach a Nebula runtime node directly to deployment host uplink bridge '${hostBridge}'

            Use a tenant/access bridge or an explicit targetContainer so underlay reachability traverses the modeled access, policy, selector, and core path.
          ''
        else
          materialization;

      overlayEntries = builtins.concatLists (
        map (
          enterpriseName:
          let
            enterpriseInventory =
              requireAttr "inventory.controlPlane.sites.${enterpriseName}" (inventorySites.${enterpriseName} or null);
            enterpriseCpm =
              requireAttr "control_plane_model.data.${enterpriseName}" (cpmData.${enterpriseName} or null);
          in
          builtins.concatLists (
            map (
              siteName:
              let
                siteInventory =
                  requireAttr "inventory.controlPlane.sites.${enterpriseName}.${siteName}"
                    (enterpriseInventory.${siteName} or null);
                siteCpm =
                  requireAttr "control_plane_model.data.${enterpriseName}.${siteName}"
                    (enterpriseCpm.${siteName} or null);
                overlays = siteInventory.overlays or { };
              in
              map (
                overlayName:
                let
                  overlayInventory =
                    requireAttr
                      "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}"
                      (overlays.${overlayName} or null);
                  overlayCpm =
                    requireAttr
                      "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}"
                      ((siteCpm.overlays or { }).${overlayName} or null);
                in
                {
                  inherit
                    enterpriseName
                    siteName
                    overlayName
                    overlayInventory
                    overlayCpm
                    ;
                }
              ) (sortedAttrNames overlays)
            ) (sortedAttrNames enterpriseInventory)
          )
        ) (sortedAttrNames inventorySites)
      );

      nebulaOverlayEntries = lib.filter (
        entry:
        let
          provider = entry.overlayInventory.provider or entry.overlayCpm.provider or null;
        in
        builtins.isString provider && provider == "nebula"
      ) overlayEntries;

      overlayPlans = builtins.listToAttrs (
        map (
          entry:
          let
            inherit (entry) enterpriseName siteName overlayName overlayInventory overlayCpm;
            overlayId = "${enterpriseName}::${siteName}::${overlayName}";

            overlayNodes =
              requireAttr
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes"
                (overlayCpm.nodes or null);
            nebula =
              requireAttr
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nebula"
                (overlayCpm.nebula or null);
            lighthouse =
              requireAttr
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nebula.lighthouse"
                (nebula.lighthouse or null);
            lighthouseNodeName =
              requireString
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nebula.lighthouse.node"
                (lighthouse.node or null);
            lighthouseNode =
              requireAttr
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes.${lighthouseNodeName}"
                (overlayNodes.${lighthouseNodeName} or null);
            ipam =
              requireAttr
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.ipam"
                (overlayCpm.ipam or null);
            ipam4 =
              requireAttr
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.ipam.ipv4"
                (ipam.ipv4 or null);
            ipam6 =
              requireAttr
                "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.ipam.ipv6"
                (ipam.ipv6 or null);
            prefixLength4 = readPrefixLength (
              requireString "${enterpriseName}.${siteName}.${overlayName}.ipam.ipv4.prefix" (ipam4.prefix or null)
            );
            prefixLength6 = readPrefixLength (
              requireString "${enterpriseName}.${siteName}.${overlayName}.ipam.ipv6.prefix" (ipam6.prefix or null)
            );
            runtimeNodes = overlayInventory.runtimeNodes or { };

            nodePlans = builtins.listToAttrs (
              map (
                nodeName:
                let
                  runtimeNode =
                    requireAttr
                      "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.runtimeNodes.${nodeName}"
                      (runtimeNodes.${nodeName} or null);
                  runtimeNodePath =
                    "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.runtimeNodes.${nodeName}";
                  renderedNode =
                    requireAttr
                      "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes.${nodeName}"
                      (overlayNodes.${nodeName} or null);
                  unsafeRoutes =
                    if builtins.isList (runtimeNode.unsafeRoutes or null) then
                      lib.filter builtins.isAttrs runtimeNode.unsafeRoutes
                    else
                      [ ];
                  routePreparation = {
                    removeRoutes = uniqueStrings (
                      map (route: route.route or null) (lib.filter (route: (route.install or true)) unsafeRoutes)
                    );
                    overlayHosts = uniqueStrings [
                      (stripPrefixLength (requireString "${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null)))
                      (stripPrefixLength (requireString "${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null)))
                    ];
                    underlayEndpoints = uniqueStrings [
                      (requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null))
                      (requireString "${overlayName}.nebula.lighthouse.endpoint6" (lighthouse.endpoint6 or null))
                    ];
                  };
                in
                {
                  name = nodeName;
                  value = {
                    inherit enterpriseName siteName overlayName overlayId;
                    overlayAddresses = [
                      (withPrefixLength (requireString "${nodeName}.addr4" (renderedNode.addr4 or null)) prefixLength4)
                      (withPrefixLength (requireString "${nodeName}.addr6" (renderedNode.addr6 or null)) prefixLength6)
                    ];
                    groups =
                      if builtins.isList (runtimeNode.groups or null) then
                        lib.filter builtins.isString runtimeNode.groups
                      else
                        [ ];
                    inherit unsafeRoutes routePreparation;
                    service = (runtimeNode.service or { }) // {
                      name = runtimeNode.service.name or "nebula-runtime";
                      interface = runtimeNode.service.interface or "nebula1";
                    };
                    materialization = validateRuntimeMaterialization runtimeNodePath runtimeNode;
                    lighthouse = {
                      node = lighthouseNodeName;
                      endpoint = requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null);
                      endpoint6 = requireString "${overlayName}.nebula.lighthouse.endpoint6" (
                        lighthouse.endpoint6 or null
                      );
                      port = builtins.toString (lighthouse.port or 4242);
                      endpoints = [
                        "${requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null)}:${
                          builtins.toString (lighthouse.port or 4242)
                        }"
                        "[${requireString "${overlayName}.nebula.lighthouse.endpoint6" (lighthouse.endpoint6 or null)}]:${
                          builtins.toString (lighthouse.port or 4242)
                        }"
                      ];
                      overlayAddresses = [
                        (withPrefixLength (requireString "${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null)) prefixLength4)
                        (withPrefixLength (requireString "${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null)) prefixLength6)
                      ];
                      overlayIps = [
                        (stripPrefixLength (requireString "${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null)))
                        (stripPrefixLength (requireString "${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null)))
                      ];
                    };
                  };
                }
              ) (sortedAttrNames runtimeNodes)
            );
          in
          {
            name = overlayId;
            value = {
              type = "nebula";
              name = overlayName;
              inherit enterpriseName siteName overlayId;
              ca = { name = caName; };
              lighthouse = {
                node = lighthouseNodeName;
                endpoint = requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null);
                endpoint6 = requireString "${overlayName}.nebula.lighthouse.endpoint6" (lighthouse.endpoint6 or null);
                port = builtins.toString (lighthouse.port or 4242);
                endpoints = [
                  "${requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null)}:${
                    builtins.toString (lighthouse.port or 4242)
                  }"
                  "[${requireString "${overlayName}.nebula.lighthouse.endpoint6" (lighthouse.endpoint6 or null)}]:${
                    builtins.toString (lighthouse.port or 4242)
                  }"
                ];
                overlayAddresses = [
                  (withPrefixLength (requireString "${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null)) prefixLength4)
                  (withPrefixLength (requireString "${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null)) prefixLength6)
                ];
                overlayIps = [
                  (stripPrefixLength (requireString "${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null)))
                  (stripPrefixLength (requireString "${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null)))
                ];
              };
              nodes = nodePlans;
            };
          }
        ) nebulaOverlayEntries
      );

      nodePlans = builtins.listToAttrs (
        builtins.concatLists (
          map (
            overlayId:
            map (
              nodeName: {
                name = nodeName;
                value = overlayPlans.${overlayId}.nodes.${nodeName};
              }
            ) (sortedAttrNames overlayPlans.${overlayId}.nodes)
          ) (sortedAttrNames overlayPlans)
        )
      );
    in
    {
      overlays = overlayPlans;
      nodes = nodePlans;
    };
in
{
  renderer = {
    buildNebulaPlan = buildNebulaPlanImpl;
    buildNebulaPlanFromPaths =
      {
        intentPath,
        inventoryPath,
        caName ? "s-router-test-lab",
      }:
      let
        controlPlane = cpmLib.compileAndBuildFromPaths {
          inputPath = intentPath;
          inventoryPath = inventoryPath;
        };
        inventory = cpmLib.readInput inventoryPath;
      in
      buildNebulaPlanImpl {
        inherit
          controlPlane
          inventory
          caName
          ;
      };
  };
}
