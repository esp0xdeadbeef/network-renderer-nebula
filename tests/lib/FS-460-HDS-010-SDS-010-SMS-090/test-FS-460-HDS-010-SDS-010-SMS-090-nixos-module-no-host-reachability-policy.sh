#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-090
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

if rg -n \
  'networking\.(firewall|nftables)|boot\.kernel\.sysctl|extra(Input|Forward)Rules|allowedUDPPorts|trustedInterfaces|ip_forward|conf\.all\.forwarding' \
  "${repo_root}/s88/Enterprise/runtime/nixos-module.nix" \
  "${repo_root}/s88/Enterprise/bootstrap/external-lighthouse-module.nix"; then
  cat >&2 <<'EOF'
FATAL network-renderer-nebula host reachability boundary violation.

The Nebula renderer may render Nebula service membership/config, but NixOS/CLAB
consumers own host firewall, nftables, kernel forwarding, and routed reachability.
EOF
  exit 1
fi

echo "PASS test-nixos-module-no-host-reachability-policy"
