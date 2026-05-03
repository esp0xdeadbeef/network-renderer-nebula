{
  lib,
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
  externalRemoteLighthouseEndpoint4 ? null,
  externalRemoteLighthouseEndpoint6 ? null,
  externalSuppressPublicLighthouseStaticMap ? false,
}:
let
  plan = import ./nixos-module/plan.nix {
    inherit
      lib
      nebulaRuntimePlan
      externalLighthouseReturnIpv4Cidrs
      externalLighthousePublicIpv4SecretPath
      externalLighthousePublicIpv6SecretPath
      externalLighthouseSshHostSecretPath
      externalPortForwardPublicIpv4SecretPath
      externalPortForwardPublicIpv6SecretPath
      externalPortForwardNodeNames
      externalRemoteLighthouseEndpoint4
      externalRemoteLighthouseEndpoint6
      externalSuppressPublicLighthouseStaticMap
      ;
  };

  caUnsealScript = builtins.readFile ./nixos-module/ca-unseal.bash;
  profileBootstrapBody = builtins.readFile ./nixos-module/profile-bootstrap.bash;
  profileBootstrapScript = ''
    set -euo pipefail

    state_dir="/persist/nebula-runtime"
    pki_dir="$state_dir/pki"
    profiles_dir="$state_dir/profiles"
    signing_ca_key="/run/nebula-runtime/unsealed/ca.key"
    runtime_nodes_json='${plan.runtimeNodesJson}'
    lighthouses_json='${plan.lighthousesJson}'
    external_port_forward_node_names_json='${plan.externalPortForwardNodeNamesJson}'
    external_lighthouse_return_ipv4_cidrs_csv='${plan.externalLighthouseReturnIpv4CidrsCsv}'
    external_lighthouse_public_ipv4_secret=${plan.externalLighthousePublicIpv4SecretPathArg}
    external_lighthouse_public_ipv6_secret=${plan.externalLighthousePublicIpv6SecretPathArg}
    external_lighthouse_ssh_host_secret=${plan.externalLighthouseSshHostSecretPathArg}
    external_port_forward_public_ipv4_secret=${plan.externalPortForwardPublicIpv4SecretPathArg}
    external_port_forward_public_ipv6_secret=${plan.externalPortForwardPublicIpv6SecretPathArg}
    external_remote_lighthouse_endpoint4=${plan.externalRemoteLighthouseEndpoint4Arg}
    external_remote_lighthouse_endpoint6=${plan.externalRemoteLighthouseEndpoint6Arg}
    external_suppress_public_lighthouse_static_map=${plan.externalSuppressPublicLighthouseStaticMapArg}
  '' + profileBootstrapBody;
in
if plan.runtimeNodeNames == [ ] then
  { }
else
  {
    environment.etc."s-router-test/nebula-bootstrap-spec.json".text =
      builtins.toJSON {
        runtimeNodes = plan.runtimeNodes;
        lighthouses = plan.lighthouses;
      };

    systemd.tmpfiles.rules =
      [
        "d /persist/nebula-runtime 0700 root root -"
        "d /persist/nebula-runtime/pki 0700 root root -"
        "d /persist/nebula-runtime/profiles 0700 root root -"
      ]
      ++ map (nodeName: "d /persist/nebula-runtime/profiles/${nodeName} 0700 root root -") plan.runtimeNodeNames;

    systemd.services.nebula-ca-unseal = {
      description = "Unlock the Nebula CA into /run for explicit issuance work";
      serviceConfig.Type = "oneshot";
      path = with pkgs; [
        bash
        coreutils
        nebula
        openssl
        util-linux
      ];
      script = caUnsealScript;
    };

    systemd.services.nebula-profile-bootstrap = {
      description = "Generate and distribute Nebula runtime profiles for s-router-test";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.Type = "oneshot";
      unitConfig.ConditionPathExists = "/run/nebula-runtime/unsealed/ca.key";
      path = with pkgs; [
        bash
        coreutils
        gnugrep
        gawk
        iproute2
        jq
        nebula
        openssh
        systemd
        util-linux
      ];
      script = profileBootstrapScript;
    };

    systemd.paths.nebula-profile-bootstrap = {
      description = "Start Nebula profile bootstrap when the CA is unsealed into /run";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "/run/nebula-runtime/unsealed/ca.key";
        Unit = "nebula-profile-bootstrap.service";
      };
    };
  }
