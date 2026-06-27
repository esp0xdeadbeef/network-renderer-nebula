#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-110
# GAMP-SCOPE: software-integration-test
# FS-982-SMS-110-RUNTIME: scoped-artifact
# FS-982-SMS-110-ARTIFACT: Nebula renderer runtime NixOS module artifact
# FS-982-SMS-110-EVIDENCE: tests/test-FS-460-HDS-010-SDS-010-SMS-010-runtime-module.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL fs982-sms110-nebula-sit: $*" >&2
  exit 1
}

evidence="tests/test-FS-460-HDS-010-SDS-010-SMS-010-runtime-module.sh"
output="$(NETWORK_REPO_DIRECT_TEST_OK=1 bash "${repo_root}/${evidence}" 2>&1)" || {
  printf '%s\n' "${output}" >&2
  fail "${evidence} failed"
}

grep -Fq "PASS test-nebula-runtime-module" <<<"${output}" \
  || fail "${evidence} did not prove Nebula runtime module artifact checks"
grep -Fq "runtime.yml" "${repo_root}/${evidence}" \
  || fail "${evidence} does not assert the generated Nebula runtime config artifact"

echo "PASS fs982-sms110-nebula-sit"
