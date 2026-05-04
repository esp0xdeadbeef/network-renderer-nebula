{
  lib,
  system,
  flakeInputs,
}:

let
  cpmLib = flakeInputs.network-control-plane-model.libBySystem.${system};
  helpers = import ./helpers.nix { inherit lib; };

  buildNebulaPlan =
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

      entries = import ./overlay-entries.nix {
        inherit lib helpers inventory;
        cpmData = cpm.data or { };
      };

      hostUplinkBridgeNames = helpers.collectHostUplinkBridgeNames inventory;

      overlays = builtins.listToAttrs (
        map (
          entry:
          import ./overlay-plan.nix {
            inherit
              lib
              helpers
              caName
              hostUplinkBridgeNames
              entry
              ;
          }
        ) entries
      );

      nodes = builtins.listToAttrs (
        builtins.concatLists (
          map (
            overlayId:
            map (nodeName: {
              name = nodeName;
              value = overlays.${overlayId}.nodes.${nodeName};
            }) (helpers.sortedAttrNames overlays.${overlayId}.nodes)
          ) (helpers.sortedAttrNames overlays)
        )
      );
    in
    { inherit overlays nodes; };

  buildNebulaBootstrapNixosModule =
    {
      pkgs,
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
      runtimeListenHosts ? { },
      externalRemoteLighthouseEndpoint4 ? null,
      externalRemoteLighthouseEndpoint6 ? null,
      externalSuppressPublicLighthouseStaticMap ? false,
    }:
    import ./bootstrap/nixos-module.nix {
      inherit
        lib
        pkgs
        nebulaRuntimePlan
        externalLighthouseReturnIpv4Cidrs
        externalLighthousePublicIpv4SecretPath
        externalLighthousePublicIpv6SecretPath
        externalLighthouseSshHostSecretPath
        externalPortForwardPublicIpv4SecretPath
        externalPortForwardPublicIpv6SecretPath
        externalPortForwardNodeNames
        runtimeListenHosts
        externalRemoteLighthouseEndpoint4
        externalRemoteLighthouseEndpoint6
        externalSuppressPublicLighthouseStaticMap
        ;
    };

  buildExternalLighthouseNixosModule =
    {
      pkgs,
      nebulaRuntimePlan ? {
        overlays = { };
        nodes = { };
      },
    }:
    import ./bootstrap/external-lighthouse-module.nix {
      inherit
        lib
        pkgs
        nebulaRuntimePlan
        ;
    };

  buildNebulaRuntimeNixosModule =
    { pkgs, nodeName }:
    import ./runtime/nixos-module.nix {
      inherit lib pkgs nodeName;
    };
in
{
  renderer = {
    buildNebulaPlan = buildNebulaPlan;
    buildNebulaBootstrapNixosModule = buildNebulaBootstrapNixosModule;
    buildExternalLighthouseNixosModule = buildExternalLighthouseNixosModule;
    buildNebulaRuntimeNixosModule = buildNebulaRuntimeNixosModule;

    buildNebulaPlanFromPaths =
      {
        intentPath,
        inventoryPath,
        caName ? "s-router-test-lab",
      }:
      buildNebulaPlan {
        controlPlane = cpmLib.compileAndBuildFromPaths {
          inputPath = intentPath;
          inventoryPath = inventoryPath;
        };
        inventory = cpmLib.readInput inventoryPath;
        inherit caName;
      };
  };
}
