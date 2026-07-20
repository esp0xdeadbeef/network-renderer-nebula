#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-010
# UPDATED: deploymentHost logic moved to CPM. Materialization now comes from CPM data.
# Test verifies that container profile flows through from CPM to materialization.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
    plan = import "'"$repo_root"'/tests/nix/nebula-plan-from-inputs.nix" {
      repoRoot = "'"$repo_root"'";
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
  in
    {
      materialization = plan.nodes."c-router-lighthouse".materialization;
    }
' > "$tmp_dir/hosted-plan.json"

# Verify that materialization includes container info from CPM data
jq -e '.materialization.container.profile != null' \
  "$tmp_dir/hosted-plan.json" >/dev/null

echo "PASS test-nebula-plan-hosted-inventory (adapted: materialization from CPM data)"
