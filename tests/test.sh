#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${NETWORK_REPO_SWEEP:-0}" != "1" && "${NETWORK_REPO_DIRECT_TEST_OK:-0}" != "1" ]]; then
  echo "WARN: direct repo tests are partial; set NETWORK_REPO_DIRECT_TEST_OK=1 for intentional focused runs, or run network-codex-agent/scripts/s-router-full-lab-rebuild-loop.sh for the locked full network-* sweep plus live validation." >&2
fi

default_jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
jobs="${TEST_JOBS:-${NEBULA_TEST_JOBS:-${default_jobs}}}"
case "${jobs}" in
  ''|*[!0-9]*|0)
    echo "error: TEST_JOBS must be a positive integer, got '${jobs}'" >&2
    exit 2
    ;;
esac

tests=(
  test-nix-file-loc.sh
  test-regression-md-resolved-states.sh
  test-FS-310-HDS-010-SDS-010-SMS-110-nebula-crit-fix.sh
  test-FS-460-HDS-010-SDS-010-SMS-021-cpm-overlay-contract-boundary.sh
  test-FS-460-HDS-010-SDS-010-SMS-090-provider-boundary-no-forwarding-policy.sh
  test-FS-460-HDS-010-SDS-010-SMS-090-provider-boundary-no-dns-egress.sh
  test-FS-460-HDS-010-SDS-010-SMS-090-nixos-module-no-host-reachability-policy.sh
  test-FS-100-HDS-010-SDS-010-SMS-010-renderer-output-provenance.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-cli-render-node.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-plan.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-plan-explicit-inputs-basic.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-plan-hosted-inventory.sh
  test-FS-460-HDS-010-SDS-010-SMS-090-plan-reject-host-uplink.sh
  test-FS-460-HDS-010-SDS-010-SMS-030-plan-reject-missing-relay.sh
  test-FS-460-HDS-010-SDS-010-SMS-041-nebula-fail-closed-contract.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-nebula-remote-egress-smt.sh
  test-FS-460-HDS-010-SDS-010-SMS-050-delegated-default-exit.sh
  test-FS-460-HDS-010-SDS-010-SMS-050-dynamic-delegated-return-route.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-delegated-prefix-secret-names.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-bootstrap-advertised-networks.sh
  test-FS-460-HDS-010-SDS-010-SMS-090-advertised-default-firewall.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-bootstrap-module.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-bootstrap-spec.sh
  test-FS-460-HDS-010-SDS-010-SMS-030-remote-lighthouse-endpoint.sh
  test-FS-460-HDS-010-SDS-010-SMS-030-public-forwarded-relay-static-map.sh
  test-FS-460-HDS-010-SDS-010-SMS-030-public-relay-endpoint-static-map.sh
  test-FS-460-HDS-010-SDS-010-SMS-050-public-ingress-runtime-facts.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-host-profile-bindmounts.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-runtime-module.sh
  test-FS-460-HDS-010-SDS-010-SMS-060-boundary-scan.sh
  test-FS-460-HDS-010-SDS-010-SMS-021-nebula-cpm-only-consumption.sh
  test-FS-460-HDS-010-SDS-010-SMS-080-output-containment.sh
  run-fs982-sms110.sh
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

declare -A pid_to_name=()
declare -A pid_to_log=()
declare -A pid_to_start=()
running=0
failures=0

wait_for_one() {
  local finished_pid
  local status=0
  wait -n -p finished_pid || status=$?

  local name="${pid_to_name[${finished_pid}]}"
  local log_file="${pid_to_log[${finished_pid}]}"
  local start="${pid_to_start[${finished_pid}]}"
  local elapsed=$((SECONDS - start))
  unset "pid_to_name[${finished_pid}]"
  unset "pid_to_log[${finished_pid}]"
  unset "pid_to_start[${finished_pid}]"
  running=$((running - 1))

  if ((status == 0)); then
    printf 'PASS %s (%ss)\n' "${name}" "${elapsed}"
  else
    printf 'FAIL %s (exit %s, %ss)\n' "${name}" "${status}" "${elapsed}" >&2
    sed "s/^/[${name}] /" "${log_file}" >&2
    failures=$((failures + 1))
  fi
}

printf 'running %s tests with up to %s concurrent jobs\n' "${#tests[@]}" "${jobs}"

for test_name in "${tests[@]}"; do
  test_path="${repo_root}/tests/${test_name}"
  log_file="${tmp_dir}/${test_name}.log"

  bash "${test_path}" >"${log_file}" 2>&1 &
  pid=$!
  pid_to_name["${pid}"]="${test_name}"
  pid_to_log["${pid}"]="${log_file}"
  pid_to_start["${pid}"]="${SECONDS}"
  running=$((running + 1))
  printf 'START %s\n' "${test_name}"

  while ((running >= jobs)); do
    wait_for_one
  done
done

while ((running > 0)); do
  wait_for_one
done

if ((failures > 0)); then
  printf 'error: %s/%s tests failed\n' "${failures}" "${#tests[@]}" >&2
  exit 1
fi

printf 'PASS %s tests\n' "${#tests[@]}"
