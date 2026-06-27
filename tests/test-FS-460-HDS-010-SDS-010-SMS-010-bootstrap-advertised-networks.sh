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
      consumerName = "s-router-test";
      externalLighthouseReturnIpv4Cidrs = [ "10.70.10.0/24" ];
      sopsProfileSecretPrefix = "nebula-profile";
      profileSecretMaterializationMode = "sops-runtime";
    };
  in
  {
    spec = builtins.fromJSON module.environment.etc."s-router-test/nebula-bootstrap-spec.json".text;
    sopsSecrets = module.sops.secrets;
  }
' > "$tmp_dir/bootstrap.json"

jq -e '
  .spec.runtimeNodes["c-router-lighthouse"].isLighthouse == true and
  .spec.runtimeNodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
  (.spec.runtimeNodes["c-router-lighthouse"].unsafeRoutes | length) == 0 and
  .spec.runtimeNodes["c-router-nebula-core"].relay.amRelay == true and
  .spec.runtimeNodes["b-router-core-nebula"].relay.relays == ["100.96.10.3"] and
  (.spec.runtimeNodes["b-router-core-nebula"].unsafeRoutes | length) > 0 and
  (.spec.runtimeNodes["b-router-core-nebula"].advertisedUnsafeNetworks | index("10.60.10.0/24") != null) and
  (.spec.runtimeNodes["b-router-core-nebula"].advertisedUnsafeNetworks | index("10.50.0.0/32") == null) and
  (.spec.runtimeNodes["b-router-core-nebula"].advertisedUnsafeNetworks | index("fd42:dead:feed:10::/64") != null) and
  (.spec.runtimeNodes["c-router-nebula-core"].advertisedUnsafeNetworks | index("10.70.10.0/24") == null) and
  .spec.lighthouses["east-west"].internal == true and
  (.spec.lighthouses["east-west"].unsafeNetworks | index("fd42:dead:beef:10::/64") != null) and
  .sopsSecrets["nebula-profile-b-router-core-nebula-key"].path == "/persist/nebula-runtime/profiles/b-router-core-nebula/b-router-core-nebula.key"
' "$tmp_dir/bootstrap.json" >/dev/null

echo "PASS test-nebula-bootstrap-advertised-networks"
