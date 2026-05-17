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
    api = flake.libBySystem.x86_64-linux.renderer;
    plan = api.buildNebulaPlanFromPaths {
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
  in
    api.buildNebulaBootstrapSpec {
      nebulaRuntimePlan = plan;
      externalPortForwardNodeNames = [ "c-router-nebula-core" ];
      externalRuntimeNodeNames = [ "c-router-nebula-core" ];
      runtimeListenHosts.c-router-nebula-core = "172.31.254.4";
      sopsProfileSecretPrefix = "nebula-profile";
    }
' > "$tmp_dir/spec.json"

jq -e '
  .runtimeNodes["c-router-lighthouse"].isLighthouse == true and
  .runtimeNodes["c-router-nebula-core"].service.listenHost == "172.31.254.4" and
  .runtimeNodes["b-router-core-nebula"].relay.relays == ["100.96.10.3"] and
  (.runtimeNodes["b-router-core-nebula"].unsafeRoutes | length) > 0 and
  .lighthouses["east-west"].internal == true
' "$tmp_dir/spec.json" >/dev/null

echo "PASS test-nebula-bootstrap-spec"
