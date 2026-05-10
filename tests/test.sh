#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${NETWORK_REPO_SWEEP:-0}" != "1" && "${NETWORK_REPO_DIRECT_TEST_OK:-0}" != "1" ]]; then
  echo "WARN: direct repo tests are partial; set NETWORK_REPO_DIRECT_TEST_OK=1 for intentional focused runs, or run network-codex-agent/scripts/s-router-full-lab-rebuild-loop.sh for the locked full network-* sweep plus live validation." >&2
fi

"${repo_root}/tests/test-nix-file-loc.sh"
"${repo_root}/tests/test-cpm-overlay-contract-boundary.sh"
"${repo_root}/tests/test-provider-boundary-no-forwarding-policy.sh"
"${repo_root}/tests/test-nebula-plan.sh"
"${repo_root}/tests/test-nebula-delegated-default-exit.sh"
"${repo_root}/tests/test-nebula-dynamic-delegated-return-route.sh"
"${repo_root}/tests/test-nebula-plan-from-paths.sh"
"${repo_root}/tests/test-nebula-bootstrap-module.sh"
"${repo_root}/tests/test-nebula-remote-lighthouse-endpoint.sh"
"${repo_root}/tests/test-nebula-runtime-module.sh"
