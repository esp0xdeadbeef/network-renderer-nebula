#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="${repo_root}/s88/Enterprise/bootstrap/nixos-module/profile-bootstrap.bash"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

awk '
  /route_lighthouse_endpoint="\$lighthouse_endpoint"/ { in_block = 1 }
  in_block { print }
  in_block && /if ! listen_supports_ipv4/ { exit }
' "$source_file" > "$tmp_dir/endpoint-selection.sh"

grep -F '[ "$profile_context" = "remote" ] \' "$tmp_dir/endpoint-selection.sh" >/dev/null || {
  echo "network-renderer-nebula: remote profiles must use the modeled internal lighthouse endpoint, not public hairpin static maps" >&2
  echo "Remove this failure only after remote install_profile contexts select external_remote_lighthouse_endpoint4/6 for lighthouse_endpoint and route_lighthouse_endpoint." >&2
  exit 1
}

grep -F 'lighthouse_endpoint="$external_remote_lighthouse_endpoint4"' "$tmp_dir/endpoint-selection.sh" >/dev/null || {
  echo "network-renderer-nebula: remote profile static_host_map must point at external_remote_lighthouse_endpoint4" >&2
  exit 1
}

grep -F 'lighthouse_endpoint6="$external_remote_lighthouse_endpoint6"' "$tmp_dir/endpoint-selection.sh" >/dev/null || {
  echo "network-renderer-nebula: remote profile static_host_map must point at external_remote_lighthouse_endpoint6 when modeled" >&2
  exit 1
}

if grep -F '[ "$profile_context" != "remote" ] \' "$tmp_dir/endpoint-selection.sh" >/dev/null; then
  echo "network-renderer-nebula: endpoint override is still restricted to non-remote profiles; this leaves Hetzner runtime nodes hairpinning through public IPv4" >&2
  exit 1
fi

echo "PASS test-nebula-remote-lighthouse-endpoint"
