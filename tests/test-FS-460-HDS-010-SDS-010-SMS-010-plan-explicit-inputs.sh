#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests=(
  test-FS-460-HDS-010-SDS-010-SMS-010-plan-explicit-inputs-basic.sh
  test-FS-460-HDS-010-SDS-010-SMS-010-plan-hosted-inventory.sh
  test-FS-460-HDS-010-SDS-010-SMS-090-plan-reject-host-uplink.sh
  test-FS-460-HDS-010-SDS-010-SMS-030-plan-reject-missing-relay.sh
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

status=0
for test_name in "${tests[@]}"; do
  bash "${repo_root}/tests/${test_name}" >"${tmp_dir}/${test_name}.log" 2>&1 &
  printf '%s\n' "$!" >"${tmp_dir}/${test_name}.pid"
done

for test_name in "${tests[@]}"; do
  pid="$(cat "${tmp_dir}/${test_name}.pid")"
  if wait "${pid}"; then
    cat "${tmp_dir}/${test_name}.log"
  else
    sed "s/^/[${test_name}] /" "${tmp_dir}/${test_name}.log" >&2
    status=1
  fi
done

if [[ "$status" -eq 0 ]]; then
  echo "PASS test-nebula-plan-explicit-inputs"
fi
exit "$status"
