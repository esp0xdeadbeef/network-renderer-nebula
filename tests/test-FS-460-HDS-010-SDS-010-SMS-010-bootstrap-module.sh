#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-010
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    system = "x86_64-linux";
    api = flake.libBySystem.${system}.renderer;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    plan = import "'"$repo_root"'/tests/nix/nebula-plan-from-inputs.nix" {
      repoRoot = "'"$repo_root"'";
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
      inherit system;
    };
    module = api.buildNebulaBootstrapNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = plan;
      consumerName = "s-router-test";
      externalPortForwardNodeNames = [ "c-router-nebula-core" ];
      externalRuntimeNodeNames = [ "c-router-nebula-core" ];
      runtimeListenHosts = {
        c-router-nebula-core = "172.31.254.4";
      };
      sopsProfileSecretPrefix = "nebula-profile";
      profileSecretMaterializationMode = "sops-runtime";
    };
    operatorModule = api.buildNebulaBootstrapNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = plan;
      consumerName = "s-router-test";
      externalPortForwardNodeNames = [ "c-router-nebula-core" ];
      externalRuntimeNodeNames = [ "c-router-nebula-core" ];
      runtimeListenHosts = {
        c-router-nebula-core = "172.31.254.4";
      };
      profileSecretMaterializationMode = "operator-unlock";
    };
    externalModule = api.buildExternalLighthouseNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = plan;
      consumerName = "s-router-test";
    };
  in
  {
    spec = builtins.fromJSON module.environment.etc."s-router-test/nebula-bootstrap-spec.json".text;
    sopsSecrets = module.sops.secrets;
    tmpfiles = module.systemd.tmpfiles.rules;
    externalNetworks = externalModule.services.nebula.networks or { };
    externalFirewall = externalModule.networking.firewall or { };
    externalSysctl = externalModule.boot.kernel.sysctl or { };
    externalTmpfiles = externalModule.systemd.tmpfiles.rules;
    activation = module.system.activationScripts.nebulaSopsProfiles;
    operator = {
      sopsSecrets = operatorModule.sops.secrets or { };
      activationScripts = operatorModule.system.activationScripts or { };
      profileTargets = builtins.fromJSON operatorModule.environment.etc."s-router-test/nebula-profile-targets.json".text;
      tmpfiles = operatorModule.systemd.tmpfiles.rules;
    };
  }
' > "$tmp_dir/bootstrap.json"

jq -e '
  (.spec.runtimeNodes["b-router-core-nebula"].routePreparation.removeRoutes
    | index("10.20.10.0/24") != null and index("fd42:dead:beef:50::/64") != null) and
  .spec.runtimeNodes["c-router-lighthouse"].isLighthouse == true and
  .spec.runtimeNodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
  (.spec.runtimeNodes["c-router-lighthouse"].unsafeRoutes | length) == 0 and
  (.spec.runtimeNodes["c-router-lighthouse"].groupsCsv | split(",") | index("lighthouse") != null) and
  .spec.runtimeNodes["c-router-nebula-core"].relay.amRelay == false and
  .spec.runtimeNodes["s-router-core-nebula"].relay.relays == [] and
  .spec.runtimeNodes["b-router-core-nebula"].relay.relays == [] and
  .spec.runtimeNodes["c-router-nebula-core"].service.listenHost == "172.31.254.4" and
  .spec.lighthouses["east-west"].internal == true and
  .sopsSecrets["nebula-profile-c-router-nebula-core-ca-crt"].path == "/persist/nebula-runtime/profiles/c-router-nebula-core/ca.crt" and
  .sopsSecrets["nebula-profile-c-router-nebula-core-crt"].path == "/persist/nebula-runtime/profiles/c-router-nebula-core/c-router-nebula-core.crt" and
  .sopsSecrets["nebula-profile-c-router-nebula-core-key"].path == "/persist/nebula-runtime/profiles/c-router-nebula-core/c-router-nebula-core.key" and
  (.spec.lighthouses["east-west"].unsafeNetworks | index("fd42:dead:beef:10::/64") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime 0700 root root -") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime/profiles/c-router-nebula-core 0700 root root -") != null) and
  .activation.deps == ["setupSecrets"] and
  (.activation.text | contains("source_path=\"/run/secrets/nebula-profile-c-router-nebula-core-ca-crt\"")) and
  (.activation.text | contains("target_path=/persist/nebula-runtime/profiles/c-router-nebula-core/ca.crt")) and
  (.activation.text | contains("missing prepared Nebula profile secret")) and
  (.activation.text | contains("exit 1")) and
  (.activation.text | contains("install -D -m 0400 -o root -g root \"$source_path\" \"$target_path\""))
' "$tmp_dir/bootstrap.json" >/dev/null

jq -e '
  (.operator.sopsSecrets | keys | length) == 0 and
  (.operator.activationScripts | has("nebulaSopsProfiles") | not) and
  .operator.profileTargets["c-router-nebula-core"].caCrt == "/persist/nebula-runtime/profiles/c-router-nebula-core/ca.crt" and
  .operator.profileTargets["c-router-nebula-core"].cert == "/persist/nebula-runtime/profiles/c-router-nebula-core/c-router-nebula-core.crt" and
  .operator.profileTargets["c-router-nebula-core"].key == "/persist/nebula-runtime/profiles/c-router-nebula-core/c-router-nebula-core.key" and
  (.operator.tmpfiles | index("d /persist/nebula-runtime/profiles/c-router-nebula-core 0700 root root -") != null)
' "$tmp_dir/bootstrap.json" >/dev/null

jq -e '
  (.externalNetworks | keys | index("lighthouse-east-west") == null) and
  (.externalFirewall | has("allowedUDPPorts") | not) and
  (.externalFirewall | has("trustedInterfaces") | not) and
  (.externalSysctl | has("net.ipv4.ip_forward") | not) and
  (.externalSysctl | has("net.ipv6.conf.all.forwarding") | not)
' "$tmp_dir/bootstrap.json" >/dev/null

source_file="${repo_root}/s88/Enterprise/bootstrap/nixos-module.nix"
! grep -F 'profile-bootstrap.bash' "$source_file" >/dev/null
! grep -F 'nebula-profile-bootstrap' "$source_file" >/dev/null
! grep -E 'ssh[[:space:]]|sops[[:space:]]+--decrypt|age[[:space:]]+--decrypt|nebula-cert|read[[:space:]]+-p' "$source_file" >/dev/null
grep -F 'sops.secrets' "$source_file" >/dev/null
grep -F 'path = entry.path;' "$source_file" >/dev/null
grep -F 'deps = [ "setupSecrets" ];' "$source_file" >/dev/null
grep -F 'profileSecretMaterializationMode = "operator-unlock"' "$0" >/dev/null
grep -F 'profileSecretMaterializationMode = "sops-runtime"' "$0" >/dev/null

echo "PASS test-nebula-bootstrap-module"
