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
      hetznerIpv4NatCidrs ? [ ],
    }:
    import ./bootstrap/nixos-module.nix {
      inherit
        lib
        pkgs
        nebulaRuntimePlan
        hetznerIpv4NatCidrs
        ;
    };

  buildHetznerLighthouseNixosModule =
    {
      pkgs,
      nebulaRuntimePlan ? {
        overlays = { };
        nodes = { };
      },
      hetznerIpv4NatCidrs ? [ ],
      externalInterface ? "ens3",
    }:
    import ./bootstrap/hetzner-lighthouse-module.nix {
      inherit
        lib
        pkgs
        nebulaRuntimePlan
        hetznerIpv4NatCidrs
        externalInterface
        ;
    };
in
{
  renderer = {
    buildNebulaPlan = buildNebulaPlan;
    buildNebulaBootstrapNixosModule = buildNebulaBootstrapNixosModule;
    buildHetznerLighthouseNixosModule = buildHetznerLighthouseNixosModule;

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
