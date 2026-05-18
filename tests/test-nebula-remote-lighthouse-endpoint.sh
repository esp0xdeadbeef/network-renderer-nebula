#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -e "${repo_root}/s88/Enterprise/bootstrap/nixos-module/profile-bootstrap.bash" ]; then
  echo "network-renderer-nebula: remote lighthouse behavior must not live in profile-bootstrap.bash" >&2
  exit 1
fi

source_file="${repo_root}/s88/Enterprise/runtime/nixos-module.nix"

grep -F 'services.nebula.networks.${networkName}' "$source_file" >/dev/null
grep -F 'staticHostMap = staticHostMap;' "$source_file" >/dev/null
grep -F 'lighthouseEndpoints = runtimeNode.lighthouse.endpoints or [ ];' "$source_file" >/dev/null
grep -F 'return value.split("/", 1)[0]' "$source_file" >/dev/null

echo "PASS test-nebula-remote-lighthouse-endpoint"
