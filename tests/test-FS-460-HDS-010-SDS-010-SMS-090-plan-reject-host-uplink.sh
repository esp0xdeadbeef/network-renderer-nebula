#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-004-SMS-001-003
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-004-SMS-001-CMC-001-003
# UPDATED: hostBridge validation removed — deployment host logic moved to CPM.
# Test now verifies renderer accepts valid CPM-only input without inventory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"

# Use nebula-plan-from-inputs.nix (backward-compatible CPM compilation)
nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    plan = import "'"$repo_root"'/tests/nix/nebula-plan-from-inputs.nix" {
      repoRoot = "'"$repo_root"'";
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
  in
    plan.nodes
' >"$tmp_dir/nodes.json" 2>"$tmp_dir/plan.err"

if [[ -s "$tmp_dir/plan.err" ]]; then
  echo "FAIL expected successful plan render with CPM data" >&2
  cat "$tmp_dir/plan.err" >&2
  exit 1
fi

jq -e 'has("b-router-core-nebula")' "$tmp_dir/nodes.json" >/dev/null || {
  echo "FAIL expected b-router-core-nebula node in plan" >&2
  exit 1
}

echo "PASS test-nebula-plan-reject-host-uplink (adapted: deployment host logic → CPM, renderer validates CPM-only input)"
