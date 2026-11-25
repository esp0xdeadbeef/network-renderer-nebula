let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  factsPath = repoRoot + "/s88/Enterprise/public-ingress-runtime-facts.nix";

  buildFacts =
    if builtins.pathExists factsPath then
      import factsPath { inherit lib; }
    else
      null;

  factsFunctionArgs =
    if buildFacts == null then
      { }
    else
      builtins.functionArgs buildFacts;

  surfaceArgumentName =
    name:
    builtins.match "runtimeForward.*Bridge" name != null;

  surfaceArguments =
    builtins.filter surfaceArgumentName (builtins.attrNames factsFunctionArgs);

  surfaceArgumentHasNoDefault =
    name: !(factsFunctionArgs.${name});

  sourceText =
    if builtins.pathExists factsPath then
      builtins.readFile factsPath
    else
      "";

  hardcodedBridgeLiteral =
    builtins.match ".*runtimeForwardHostBridge.*\\?.*\"[^\"]+\".*" sourceText != null;

  modeledSurfaceName = "br-modeled-uplink";

  checks = {
    modeled_surface_passes_through =
      buildFacts != null
      && builtins.length surfaceArguments == 1
      && builtins.head surfaceArguments
        == "runtimeForwardHostBridge"
      && !(factsFunctionArgs.runtimeForwardHostBridge);

    missing_surface_does_not_default =
      buildFacts == null
      || (
        surfaceArgumentHasNoDefault "runtimeForwardHostBridge"
      );

    surface_argument_is_required =
      buildFacts != null
      && surfaceArguments != [ ]
      && !(factsFunctionArgs.runtimeForwardHostBridge or false);

    no_hardcoded_bridge_literal =
      !hardcodedBridgeLiteral;

    surface_name_is_not_class_authority =
      lib.hasPrefix "br-" modeledSurfaceName
      && builtins.match ".*br-[a-z].*" sourceText == null;
  };

  failed = lib.filter (name: checks.${name} != true) (builtins.attrNames checks);
in
{
  ok = failed == [ ];
  inherit checks failed;
  coverage = {
    factsModulePresent = buildFacts != null;
    surfaceArguments = surfaceArguments;
    modeledSurfaceName = modeledSurfaceName;
  };
}
