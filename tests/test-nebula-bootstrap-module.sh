#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
inventory_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix"

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
      externalPortForwardNodeNames = [ "c-router-nebula-core" ];
      externalRuntimeNodeNames = [ "c-router-nebula-core" ];
      runtimeListenHosts = {
        c-router-nebula-core = "172.31.254.4";
      };
      sopsProfileSecretPrefix = "nebula-profile";
    };
    externalModule = api.buildExternalLighthouseNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = plan;
    };
  in
  {
    spec = builtins.fromJSON module.environment.etc."s-router-test/nebula-bootstrap-spec.json".text;
    sopsSecrets = module.sops.secrets;
    tmpfiles = module.systemd.tmpfiles.rules;
    externalNetworks = externalModule.services.nebula.networks or { };
    externalFirewall = externalModule.networking.firewall;
    externalTmpfiles = externalModule.systemd.tmpfiles.rules;
  }
' > "$tmp_dir/bootstrap.json"

jq -e '
  (.spec.runtimeNodes["b-router-core-nebula"].routePreparation.removeRoutes
    | index("10.20.10.0/24") != null and index("fd42:dead:beef:50::/64") != null) and
  .spec.runtimeNodes["c-router-lighthouse"].isLighthouse == true and
  .spec.runtimeNodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
  (.spec.runtimeNodes["c-router-lighthouse"].unsafeRoutes | length) == 0 and
  (.spec.runtimeNodes["c-router-lighthouse"].groupsCsv | split(",") | index("lighthouse") != null) and
  .spec.runtimeNodes["c-router-nebula-core"].relay.amRelay == true and
  .spec.runtimeNodes["s-router-core-nebula"].relay.relays == ["100.96.10.3"] and
  .spec.runtimeNodes["b-router-core-nebula"].relay.relays == ["100.96.10.3"] and
  .spec.runtimeNodes["c-router-nebula-core"].service.listenHost == "172.31.254.4" and
  .spec.lighthouses["east-west"].internal == true and
  .sopsSecrets["nebula-profile-c-router-nebula-core-ca-crt"].path == "/persist/nebula-runtime/profiles/c-router-nebula-core/ca.crt" and
  .sopsSecrets["nebula-profile-c-router-nebula-core-crt"].path == "/persist/nebula-runtime/profiles/c-router-nebula-core/c-router-nebula-core.crt" and
  .sopsSecrets["nebula-profile-c-router-nebula-core-key"].path == "/persist/nebula-runtime/profiles/c-router-nebula-core/c-router-nebula-core.key" and
  (.spec.lighthouses["east-west"].unsafeNetworks | index("fd42:dead:beef:10::/64") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime 0700 root root -") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime/profiles/c-router-nebula-core 0700 root root -") != null)
' "$tmp_dir/bootstrap.json" >/dev/null

jq -e '
  (.externalNetworks | keys | index("lighthouse-east-west") == null) and
  (.externalFirewall.allowedUDPPorts | index(4242) == null)
' "$tmp_dir/bootstrap.json" >/dev/null

source_file="${repo_root}/s88/Enterprise/bootstrap/nixos-module.nix"
! grep -F 'profile-bootstrap.bash' "$source_file" >/dev/null
! grep -F 'nebula-profile-bootstrap' "$source_file" >/dev/null
grep -F 'sops.secrets' "$source_file" >/dev/null
grep -F 'path = entry.path;' "$source_file" >/dev/null

echo "PASS test-nebula-bootstrap-module"
