#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
labs_root="$(nix flake metadata --json "$repo_root" | jq -r '.locks.nodes.network-labs.original.owner' >/dev/null 2>&1 && true)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

intent_path="/home/deadbeef/github/network-labs/examples/tri-site-dual-wan-overlay-integration-bgp/intent.nix"
inventory_path="/home/deadbeef/github/network-labs/examples/tri-site-dual-wan-overlay-integration-static/inventory-base.nix"

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
  .overlays["espbranch::site-b::east-west"].lighthouse.endpoint == "46.224.173.254" and
  .nodes["hostile-node01"].overlayAddresses[0] == "100.96.10.30/24" and
  .nodes["hostile-node01"].overlayAddresses[1] == "fd42:dead:beef:ee::30/64" and
  .nodes["branch-node01"].materialization.container.hostBridge == "branch"
' "$tmp_dir/plan.json" >/dev/null

echo "PASS test-nebula-plan"
