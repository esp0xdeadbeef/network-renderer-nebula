#!/usr/bin/env bash
set -uo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

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

mapfile -t tests < <(
  find "${repo_root}/tests" -maxdepth 1 -regextype posix-extended \( -type f -o -type l \) \
    \( -name 'test-*.sh' -o -regex '.*\/FS-[0-9]+-HDS-[0-9]+-SDS-[0-9]+-SMS-[0-9]+\.sh' \) \
    ! -name 'test.sh' -printf '%f\n' | LC_ALL=C sort
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
