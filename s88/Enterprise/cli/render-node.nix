{ lib
, renderer
, cpmPath
, nodeName
, overlayId ? null
, extraNode ? false
, addr4 ? null
, addr6 ? null
, groups ? [ ]
,
}:

let
  readJson = path: builtins.fromJSON (builtins.readFile path);
  input = readJson cpmPath;

  hasRuntimePlan = builtins.isAttrs (input.nebulaRuntimePlan or null);
  hasControlPlane = builtins.isAttrs (input.controlPlane or null) || builtins.isAttrs (input.control_plane_model or null);
  controlPlane = input.controlPlane or input;

  runtimePlan =
    if hasRuntimePlan then
      input.nebulaRuntimePlan
    else if hasControlPlane then
      renderer.buildNebulaPlan
        {
          inherit controlPlane;
        }
    else
      throw ''
        network-renderer-nebula: --cpm must point to JSON containing either
        nebulaRuntimePlan, or CPM controlPlane/control_plane_model data.
      '';

  selectedOverlayId =
    if overlayId != null then
      overlayId
    else if builtins.hasAttr nodeName (runtimePlan.nodes or { }) then
      runtimePlan.nodes.${nodeName}.overlayId or null
    else
      null;

  overlay =
    if selectedOverlayId != null && builtins.hasAttr selectedOverlayId (runtimePlan.overlays or { }) then
      runtimePlan.overlays.${selectedOverlayId}
    else if selectedOverlayId == null then
      throw "network-renderer-nebula: --overlay is required when rendering a non-modeled node"
    else
      throw "network-renderer-nebula: unknown overlay '${selectedOverlayId}'";

  requireExtraString = flag: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nebula: ${flag} is required for --extra-node";

  unmanagedRuntimeNode =
    let
      address4 = requireExtraString "--addr4" addr4;
      address6 = requireExtraString "--addr6" addr6;
      prefix4 = builtins.elemAt (lib.splitString "/" address4) 1;
      prefix6 = builtins.elemAt (lib.splitString "/" address6) 1;
      host4 = builtins.head (lib.splitString "/" address4);
      host6 = builtins.head (lib.splitString "/" address6);
      withPrefix = address: prefix:
        let
          parts = lib.splitString "/" address;
        in
        if builtins.length parts > 1 then address else "${address}/${prefix}";
    in
    {
      enterpriseName = overlay.enterpriseName or null;
      siteName = overlay.siteName or null;
      overlayName = overlay.name or null;
      overlayId = selectedOverlayId;
      overlayAddresses = [
        (withPrefix address4 prefix4)
        (withPrefix address6 prefix6)
      ];
      groups = lib.unique (groups ++ [ "unmanaged" ]);
      service = {
        name = "nebula-runtime";
        interface = "nebula1";  # unmanaged nodes keep hardcoded interface: renderer owns the interface naming convention for unmanaged extras
      };
      materialization = {
        unmanaged = true;
      };
      relay = {
        amRelay = false;
        useRelays = false;
        relays = [ ];
        nodes = [ ];
      };
      lighthouse = overlay.lighthouse;
      unsafeRoutes = [ ];
      dynamicFirewallCidrs = [ ];
      dynamicUnsafeRoutes = [ ];
      routePreparation = {
        removeRoutes = [ ];
        overlayHosts = overlay.lighthouse.overlayIps or [ ];
        underlayEndpoints = lib.filter builtins.isString [
          (overlay.lighthouse.endpoint or null)
          (overlay.lighthouse.endpoint6 or null)
        ];
      };
      nebulaNetwork.settings = {
        nebulaFirewallRules = {
          inbound = [
            {
              port = "any";
              proto = "any";
              host = "any";
              local_cidr = "${host4}/32";
            }
            {
              port = "any";
              proto = "any";
              host = "any";
              local_cidr = "${host6}/128";
            }
          ];
          outbound = [
            {
              port = "any";
              proto = "any";
              host = "any";
              local_cidr = "${host4}/32";
            }
            {
              port = "any";
              proto = "any";
              host = "any";
              local_cidr = "${host6}/128";
            }
          ];
        };
      };
    };

  runtimeNode =
    if builtins.hasAttr nodeName (runtimePlan.nodes or { }) then
      runtimePlan.nodes.${nodeName}
    else if extraNode then
      unmanagedRuntimeNode
    else
      throw "network-renderer-nebula: unknown runtime node '${nodeName}'; pass --extra-node with explicit overlay and addresses for unmanaged members";
in
{
  inherit nodeName selectedOverlayId runtimeNode;
}
