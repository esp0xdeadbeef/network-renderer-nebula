{
  lib,
  system,
  flakeInputs,
}:

let
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
      inherit
        (import ./deployment-hosts.nix {
          inherit lib helpers inventory;
        })
        runtimeNodeDeploymentHostFor
        ;

      rawOverlays = builtins.listToAttrs (
        map (
          entry:
          import ./overlay-plan.nix {
            inherit
              lib
              helpers
              caName
              hostUplinkBridgeNames
              runtimeNodeDeploymentHostFor
              entry
              ;
          }
        ) entries
      );

      rawNodeEntries = builtins.concatLists (
        map (
          overlayId:
          map (nodeName: {
            name = nodeName;
            value = rawOverlays.${overlayId}.nodes.${nodeName};
          }) (helpers.sortedAttrNames rawOverlays.${overlayId}.nodes)
        ) (helpers.sortedAttrNames rawOverlays)
      );

      rawNodes =
        (import ./node-merge.nix { inherit lib helpers; }).mergeRawNodeEntries rawNodeEntries;

      inherit
        (import ./relay-resolution.nix {
          inherit helpers rawNodes;
        })
        relayForNode
        ;
      relayStaticHostMap = import ./relay-static-host-map.nix { inherit lib helpers; };

      baseNodes =
        builtins.mapAttrs (
          nodeName: node:
          node
          // {
            relay = relayForNode nodeName node;
          }
        ) rawNodes;

      nodes = builtins.mapAttrs (_: relayStaticHostMap.addToNode baseNodes) baseNodes;

      overlays =
        builtins.mapAttrs (
          overlayId: overlay:
          overlay
          // {
            nodes = builtins.mapAttrs (nodeName: _: nodes.${nodeName}) overlay.nodes;
          }
        ) rawOverlays;
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
      externalRuntimeNodeNames ? externalPortForwardNodeNames,
      runtimeListenHosts ? { },
      externalRemoteLighthouseEndpoint4 ? null,
      externalRemoteLighthouseEndpoint6 ? null,
      externalRemoteLighthouseEndpoint4SecretPath ? null,
      externalRemoteLighthouseEndpoint6SecretPath ? null,
      externalSuppressPublicLighthouseStaticMap ? false,
      sopsProfileSecretPrefix ? null,
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
        externalRuntimeNodeNames
        runtimeListenHosts
        externalRemoteLighthouseEndpoint4
        externalRemoteLighthouseEndpoint6
        externalRemoteLighthouseEndpoint4SecretPath
        externalRemoteLighthouseEndpoint6SecretPath
        externalSuppressPublicLighthouseStaticMap
        sopsProfileSecretPrefix
        ;
    };

  buildNebulaBootstrapSpec = import ./bootstrap/spec-api.nix { inherit lib; };

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
    {
      pkgs,
      nodeName,
      runtimeNode,
      externalRemoteLighthouseEndpoint4SecretPath ? null,
      externalRemoteLighthouseEndpoint6SecretPath ? null,
    }:
    import ./runtime/nixos-module.nix {
      inherit
        lib
        pkgs
        nodeName
        runtimeNode
        externalRemoteLighthouseEndpoint4SecretPath
        externalRemoteLighthouseEndpoint6SecretPath
        ;
    };
in
{
  renderer = {
    buildNebulaPlan = buildNebulaPlan;
    buildNebulaBootstrapSpec = buildNebulaBootstrapSpec;
    buildNebulaBootstrapNixosModule = buildNebulaBootstrapNixosModule;
    buildExternalLighthouseNixosModule = buildExternalLighthouseNixosModule;
    buildNebulaRuntimeNixosModule = buildNebulaRuntimeNixosModule;
  };
}
