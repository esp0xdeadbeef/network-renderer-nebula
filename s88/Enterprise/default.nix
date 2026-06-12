{ lib
, system
, flakeInputs
,
}:

let
  helpers = import ./helpers.nix { inherit lib; };

  buildNebulaPlan = import ./plan-api.nix { inherit lib helpers; };

  selectHostedNebulaRuntimePlan = import ./hosted-runtime-plan.nix { inherit lib; };

  selectDeploymentNebulaRuntimePlan = import ./deployment-runtime-plan.nix { inherit lib; };

  runtimeContainerNameForHost = import ./runtime-container-name.nix { inherit lib; };

  selectHostNatIngressTarget = import ./host-nat-ingress-target.nix { inherit lib; };

  buildNebulaPublicIngressRuntimeFacts = import ./public-ingress-runtime-facts.nix { inherit lib; };

  delegatedPrefixSecretNames = import ./delegated-prefix-secret-names.nix { inherit lib; };

  buildRuntimeSecretMounts = import ./runtime-secret-mounts.nix { inherit lib; };

  buildNebulaBootstrapNixosModule =
    { pkgs
    , nebulaRuntimePlan ? {
        overlays = { };
        nodes = { };
      }
    , consumerName ? "s-router-test"
    , externalLighthouseReturnIpv4Cidrs ? [ ]
    , externalLighthousePublicIpv4SecretPath ? null
    , externalLighthousePublicIpv6SecretPath ? null
    , externalLighthouseSshHostSecretPath ? externalLighthousePublicIpv4SecretPath
    , externalPortForwardPublicIpv4SecretPath ? externalLighthousePublicIpv4SecretPath
    , externalPortForwardPublicIpv6SecretPath ? externalLighthousePublicIpv6SecretPath
    , externalPortForwardNodeNames ? [ ]
    , externalRuntimeNodeNames ? externalPortForwardNodeNames
    , runtimeListenHosts ? { }
    , externalRemoteLighthouseEndpoint4 ? null
    , externalRemoteLighthouseEndpoint6 ? null
    , externalRemoteLighthouseEndpoint4SecretPath ? null
    , externalRemoteLighthouseEndpoint6SecretPath ? null
    , externalSuppressPublicLighthouseStaticMap ? false
    , sopsProfileSecretPrefix ? null
    , profileSecretMaterializationMode ? null
    ,
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
        profileSecretMaterializationMode
        consumerName
        ;
    };

  buildNebulaBootstrapSpec = import ./bootstrap/spec-api.nix { inherit lib; };

  buildExternalLighthouseNixosModule =
    { pkgs
    , nebulaRuntimePlan ? {
        overlays = { };
        nodes = { };
      }
    , consumerName ? "s-router-test"
    ,
    }:
    import ./bootstrap/external-lighthouse-module.nix {
      inherit
        lib
        pkgs
        nebulaRuntimePlan
        consumerName
        ;
    };

  buildNebulaRuntimeNixosModule =
    { pkgs
    , nodeName
    , runtimeNode
    , externalRemoteLighthouseEndpoint4SecretPath ? null
    , externalRemoteLighthouseEndpoint6SecretPath ? null
    ,
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
    inherit buildNebulaPlan selectHostedNebulaRuntimePlan selectDeploymentNebulaRuntimePlan runtimeContainerNameForHost
      selectHostNatIngressTarget buildNebulaPublicIngressRuntimeFacts delegatedPrefixSecretNames buildRuntimeSecretMounts
      buildNebulaBootstrapSpec buildNebulaBootstrapNixosModule buildExternalLighthouseNixosModule buildNebulaRuntimeNixosModule;
  };
}
