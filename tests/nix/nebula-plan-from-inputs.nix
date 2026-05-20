{ repoRoot
, intentPath
, inventoryPath
, system ? "x86_64-linux"
,
}:

let
  flake = builtins.getFlake ("path:" + repoRoot);
  api = flake.libBySystem.${system}.renderer;
  cpmLib = flake.inputs.network-control-plane-model.libBySystem.${system};
in
api.buildNebulaPlan {
  controlPlane = cpmLib.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
  };
  inventory = cpmLib.readInput inventoryPath;
}
