#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-090
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

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
