#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

intent_path="/home/deadbeef/github/network-labs/examples/s-router-test-three-site/intent.nix"
inventory_path="/home/deadbeef/github/network-labs/examples/s-router-test-three-site/inventory-base.nix"

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
  .overlays["esp0xdeadbeef::site-c::site-c-storage"].lighthouse.port == "4243" and
  .nodes["nebula-core"].materialization.container.profile == "core-client" and
  .nodes["nas-node01"].materialization.container.profile == "storage-client"
' "$tmp_dir/plan.json" >/dev/null

echo "PASS test-nebula-plan-from-paths"
