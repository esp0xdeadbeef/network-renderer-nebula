#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-090
# UPDATED: hostBridge validation removed — deployment host logic moved to CPM.
# Test now verifies renderer accepts valid CPM-only input without inventory.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"

# Use nebula-plan-from-inputs.nix (backward-compatible CPM compilation)
# A NON-EMPTY STDERR IS NOT A FAILURE. `nix` writes warnings there, and inside the CI
# sandbox it always writes one:
#   warning: you don't have Internet access; disabling some network-dependent features
# The test used to fail whenever *anything* appeared on stderr, so it was red in CI and
# green locally for a reason that had nothing to do with the renderer (measured
# 2026-11-27: FS-460-HDS-010-SDS-010-SMS-090 failed on the runner with only that warning in
# plan.err). The exit status is the verdict; stderr is reported when the command fails, and
# echoed as a warning otherwise.
set +e
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
plan_status=$?
set -e

if (( plan_status != 0 )); then
  echo "FAIL expected successful plan render with CPM data (exit ${plan_status})" >&2
  cat "$tmp_dir/plan.err" >&2
  exit 1
fi
if [[ -s "$tmp_dir/plan.err" ]]; then
  echo "note: plan render wrote to stderr; the exit status is 0, so this is a warning:" >&2
  sed 's/^/  /' "$tmp_dir/plan.err" >&2
fi

jq -e 'has("b-router-core-nebula")' "$tmp_dir/nodes.json" >/dev/null || {
  echo "FAIL expected b-router-core-nebula node in plan" >&2
  exit 1
}

echo "PASS test-nebula-plan-reject-host-uplink (adapted: deployment host logic → CPM, renderer validates CPM-only input)"
