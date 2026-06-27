#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-110
# GAMP-SCOPE: software-module-test
# FS-982-SMS-110-RUNTIME: scoped-artifact
# FS-982-SMS-110-ARTIFACT: Nebula renderer remote-egress plan artifact
# FS-982-SMS-110-EVIDENCE: tests/test-FS-460-HDS-010-SDS-010-SMS-010-nebula-remote-egress-smt.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL fs982-sms110-nebula-smt: $*" >&2
  exit 1
}

evidence="tests/test-FS-460-HDS-010-SDS-010-SMS-010-nebula-remote-egress-smt.sh"
output="$(NETWORK_REPO_DIRECT_TEST_OK=1 bash "${repo_root}/${evidence}" 2>&1)" || {
  printf '%s\n' "${output}" >&2
  fail "${evidence} failed"
}

grep -Fq "PASS fs460-nebula-remote-egress-smt" <<<"${output}" \
  || fail "${evidence} did not prove Nebula remote-egress artifact checks"
grep -Fq "missingPeerRejected" "${repo_root}/${evidence}" \
  || fail "${evidence} does not assert missing peer-site rejection"

echo "PASS fs982-sms110-nebula-smt"
