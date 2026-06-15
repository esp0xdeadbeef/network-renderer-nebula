#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-002-SMS-001-005
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-002-SMS-001-CMC-001-005
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -e "${repo_root}/s88/Enterprise/bootstrap/nixos-module/profile-bootstrap.bash" ]; then
  echo "network-renderer-nebula: remote lighthouse behavior must not live in profile-bootstrap.bash" >&2
  exit 1
fi

source_file="${repo_root}/s88/Enterprise/runtime/nixos-module.nix"
dynamic_source_file="${repo_root}/s88/Enterprise/runtime/dynamic-static-host-map-prestart.nix"

grep -F 'services.nebula.networks.${networkName}' "$source_file" >/dev/null
grep -F 'staticHostMap = staticHostMap;' "$source_file" >/dev/null
grep -F 'lighthouseEndpoints = runtimeNode.lighthouse.endpoints or [ ];' "$source_file" >/dev/null
grep -F 'dynamic-static-host-map-prestart.nix' "$source_file" >/dev/null
grep -F 'network = ipaddress.ip_network(value, strict=False)' "$dynamic_source_file" >/dev/null
grep -F 'return str(network.network_address + 1)' "$dynamic_source_file" >/dev/null
grep -F 'return value.split("/", 1)[0]' "$dynamic_source_file" >/dev/null

echo "PASS test-nebula-remote-lighthouse-endpoint"
