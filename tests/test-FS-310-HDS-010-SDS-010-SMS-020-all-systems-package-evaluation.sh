#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL FS-310-HDS-010-SDS-010-SMS-020 all-systems package evaluation: %s\n' "$1" >&2
  exit 1
}

for system in x86_64-linux aarch64-linux; do
  drv_path="$(nix eval \
    --option allow-import-from-derivation false \
    --raw "${repo_root}#packages.${system}.default.drvPath")" \
    || fail "${system} package requires import-from-derivation"
  [[ "${drv_path}" =~ ^/nix/store/[a-z0-9]{32}-network-renderer-nebula\.drv$ ]] \
    || fail "${system} package did not emit a derivation path"

  app_program="$(nix eval \
    --option allow-import-from-derivation false \
    --raw "${repo_root}#apps.${system}.default.program")" \
    || fail "${system} app requires import-from-derivation"
  [[ "${app_program}" == /nix/store/*-network-renderer-nebula/bin/network-renderer-nebula ]] \
    || fail "${system} app did not reference its package output"
done

if rg -n 'builtins\.readFile[[:space:]]+executable' \
  "${repo_root}/flake.nix" "${repo_root}/s88/Enterprise/package.nix" >/dev/null; then
  fail 'package template still reads a derivation during evaluation'
fi

printf 'PASS FS-310-HDS-010-SDS-010-SMS-020 all-systems package evaluation\n'
