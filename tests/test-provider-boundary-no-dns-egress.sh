#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-006-SMS-001-003
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-006-SMS-001-CMC-001-003
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if rg -n \
  'services\.(unbound|resolved|dnsmasq|kresd)|networking\.nameservers|resolvconf|systemd\.network\.networks\..*DNS' \
  "${repo_root}/s88/Enterprise" \
  --glob '*.nix'; then
  cat >&2 <<'EOF'
FATAL network-renderer-nebula DNS egress boundary violation.

Nebula provider rendering may emit Nebula runtime membership/config only.
Resolver services, nameservers, and DNS egress policy belong to CPM and the
target renderer or runtime consumer.
EOF
  exit 1
fi

echo "PASS test-provider-boundary-no-dns-egress"
