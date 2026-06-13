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
in
api.buildNebulaPlan {
  controlPlane = actualControlPlane;
}
