{ repoRoot
, controlPlane ? null
, intentPath ? null
, inventoryPath ? null
, system ? "x86_64-linux"
,
}:

let
  flake = builtins.getFlake ("path:" + repoRoot);
  api = flake.libBySystem.${system}.renderer;
  cpmLib = flake.inputs.network-control-plane-model.libBySystem.${system};

  # Accept pre-compiled CPM (preferred) or compile from paths (backward compat)
  actualControlPlane =
    if controlPlane != null then controlPlane
    else if intentPath != null && inventoryPath != null then
      cpmLib.compileAndBuildFromPaths {
        inputPath = intentPath;
        inherit inventoryPath;
      }
    else throw "nebula-plan-from-inputs: provide controlPlane or intentPath+inventoryPath";
  # The overlay plan maps canonical content, not the control-plane model
  # (RR_RAW_CPM_INPUT). A CPM is an INPUT here, so project the canonical section
  # from it and hand that to the plan -- the same content production receives,
  # just derived locally instead of travelling through a released bundle.
  canonicalContent =
    flake.inputs.network-realization-model.lib.canonicalFor (actualControlPlane.control_plane_model or actualControlPlane);
in
api.buildNebulaPlan {
  controlPlane = actualControlPlane;
  inherit canonicalContent;
}
