{ lib }:

{ nebulaRuntimePlan
, deploymentHostName ? null
, excludedNodeNames ? [ ]
, extraNodeNames ? [ ]
,
}:
let
  nodeBelongsToHost =
    _nodeName: node:
    let
      deploymentHost = (node.materialization or { }).deploymentHost or null;
    in
    !(builtins.isString deploymentHost)
    || deploymentHost == ""
    || deploymentHost == deploymentHostName;

  selectedNodes =
    lib.filterAttrs
      (
        nodeName: node:
          (
            nodeBelongsToHost nodeName node
            || builtins.elem nodeName extraNodeNames
          )
          && !(builtins.elem nodeName excludedNodeNames)
      )
      (nebulaRuntimePlan.nodes or { });

  selectOverlay =
    _overlayId: overlay:
    overlay
    // {
      runtimeNodes =
        if builtins.isAttrs (overlay.runtimeNodes or null) then
          lib.filterAttrs
            (nodeName: _: builtins.hasAttr nodeName selectedNodes)
            (builtins.removeAttrs overlay.runtimeNodes excludedNodeNames)
        else
          overlay.runtimeNodes or { };
    };
in
nebulaRuntimePlan
  // {
  nodes = selectedNodes;
  overlays = builtins.mapAttrs selectOverlay (nebulaRuntimePlan.overlays or { });
}
