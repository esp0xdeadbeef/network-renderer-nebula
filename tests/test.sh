#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/tests/test-nix-file-loc.sh"
"${repo_root}/tests/test-nebula-plan.sh"
"${repo_root}/tests/test-nebula-plan-from-paths.sh"
"${repo_root}/tests/test-nebula-bootstrap-module.sh"
