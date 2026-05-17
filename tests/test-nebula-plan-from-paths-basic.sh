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
  in
    api.buildNebulaPlanFromPaths {
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    }
' > "$tmp_dir/plan.json"

jq -e '
  .overlays["esp0xdeadbeef::site-a::east-west"].lighthouse.port == "4242" and
  .overlays["esp0xdeadbeef::site-c::east-west"].lighthouse.node == "c-router-lighthouse" and
  (.nodes | has("nebula-core") | not) and
  .nodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
  .nodes["s-router-core-nebula"].materialization.container.profile == "core-router-nebula" and
  .nodes["s-router-core-nebula"].relay.relays == ["100.96.10.3"] and
  .nodes["b-router-core-nebula"].relay.relays == ["100.96.10.3"] and
  .nodes["c-router-nebula-core"].relay.amRelay == true and
  .nodes["c-router-nebula-core"].materialization.container.profile == "core-router-nebula"
' "$tmp_dir/plan.json" >/dev/null

echo "PASS test-nebula-plan-from-paths-basic"
