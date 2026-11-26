#!/usr/bin/env bash
# GAMP-ID: FS-320-HDS-050-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# Nebula renderer construction test for the attachment surface binding module
# FS-320-HDS-050-SDS-010-SMS-010.
#
# The Nebula renderer materializes a runtime container whose public-ingress
# path attaches to a host bridge. That bridge is a host-facing attachment
# surface, and FS-320-HDS-050-SDS-010-SMS-010 says the named surface is used as
# given. This renderer used to supply a renderer-local default for it; the
# argument is required now, and the test fails if a default comes back.
#
# A provider renderer has no more authority to choose a host attachment
# surface than a forwarding renderer has to choose a NIC. The same rule
# applies to every renderer; the surface class differs, the authority does
# not. A defaulted bridge is a substitution the model never authorized: it
# silently wires the public-ingress path to a bridge nobody declared, and the
# site that lacks `br-wan` fails at activation with a name the model never
# mentioned.
#
# Predicates:
#   1. no renderer-local default for a host attachment surface.
#   2. when a surface is modeled, it is carried through unchanged.
#   3. a missing surface is a failure or limitation, not a default fill.
#   4. the surface class is not inferred from the surface name.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
cd "${repo_root}"

trace_id="${SMS_TEST_TRACE_ID:-FS-320-HDS-050-SDS-010-SMS-010}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

all_checks_passed=true
record_pass() { echo "PASS ${trace_id}: $1"; }
record_fail() { echo "FAIL ${trace_id}: $1" >&2; all_checks_passed=false; }

public_ingress_facts="s88/Enterprise/public-ingress-runtime-facts.nix"

echo "--- Predicate 1: no renderer-local default for a host attachment surface ---"

if [[ ! -f "${public_ingress_facts}" ]]; then
  record_fail "public-ingress runtime facts module is absent: ${public_ingress_facts}"
else
  defaulted_surface_args="$(
    grep -nE '^\s*,\s*runtimeForward[A-Za-z]*Bridge\s*\?\s*"' "${public_ingress_facts}" || true
  )"
  if [[ -n "${defaulted_surface_args}" ]]; then
    record_fail "host attachment surface carries a renderer-local default: ${defaulted_surface_args//$'\n'/ | }"
    record_fail "a provider renderer shall not choose a host attachment surface; the surface identity is modeled authority, and a default is a substitution the model never authorized"
  else
    record_pass "no host attachment surface is defaulted in ${public_ingress_facts}"
  fi

  required_surface_args="$(
    grep -nE '^\s*,\s*runtimeForward[A-Za-z]*Bridge\s*$' "${public_ingress_facts}" || true
  )"
  if [[ -n "${required_surface_args}" ]]; then
    record_pass "the host attachment surface is a required argument (no default path remains)"
  else
    record_fail "the host attachment surface is not a required argument; without one the renderer has no authority to bind it"
  fi
fi

echo ""
echo "--- Predicate 2: surface identity is not derived from a name ---"

name_derived_surface="$(
  grep -rnE 'hasPrefix\s+"br-|hasInfix\s+"br-|==\s*"br-[a-z]' s88 2>/dev/null || true
)"
if [[ -n "${name_derived_surface}" ]]; then
  record_fail "surface class is inferred from the surface name: ${name_derived_surface//$'\n'/ | }"
else
  record_pass "surface class is not inferred from the surface name"
fi

echo ""
echo "--- Predicate 3: modeled surface passes through unchanged ---"

result_json="${tmp_dir}/${trace_id}.json"
stderr_file="${tmp_dir}/${trace_id}.stderr"

if REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json --file tests/nix/fs320-hds050-sds010-sms010-attachment-surface-binding.nix \
  >"${result_json}" 2>"${stderr_file}"
then
  if [[ "$(jq -r '.checks.modeled_surface_passes_through // false' "${result_json}" 2>/dev/null || echo false)" == "true" ]]; then
    record_pass "modeled host attachment surface reaches the runtime facts unchanged"
  else
    record_fail "modeled host attachment surface does not reach the runtime facts unchanged"
  fi

  if [[ "$(jq -r '.checks.missing_surface_does_not_default // false' "${result_json}" 2>/dev/null || echo false)" == "true" ]]; then
    record_pass "a missing host attachment surface does not fall back to a renderer default"
  else
    record_fail "a missing host attachment surface falls back to a renderer default instead of failing"
  fi
else
  record_fail "attachment surface binding could not be evaluated: $(head -3 "${stderr_file}")"
fi

echo ""
if ${all_checks_passed}; then
  echo "PASS ${trace_id} — Nebula renderer binds only modeled attachment surfaces."
  exit 0
fi

echo "FAIL ${trace_id} — the Nebula renderer chooses a host attachment surface the model did not declare. Expected failing state until the surface is modeled authority." >&2
exit 1
