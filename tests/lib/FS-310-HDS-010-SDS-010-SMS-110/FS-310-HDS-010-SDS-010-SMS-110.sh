#!/usr/bin/env bash
# CMC: FS-310-HDS-010-SDS-010-SMS-110 Nebula critical/high behavioral defaults remediation
# Verifies 7 behavioral defaults replaced with fail-closed throw diagnostics per commit b918ddc.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
failures=0

# ============================================================
# Phase 1: Source-scan — confirm old behavioral defaults are absent
# ============================================================

# NE-CRIT-1: lighthouse.port or 4242
if rg -n 'or\s+4242' "${repo_root}/s88" --glob '*.nix' >/dev/null 2>&1; then
  echo "FAIL: NE-CRIT-1 — 'or 4242' (lighthouse port default) still present in source" >&2
  rg -n 'or\s+4242' "${repo_root}/s88" --glob '*.nix' >&2
  failures=$((failures + 1))
else
  echo "PASS NE-CRIT-1: 'or 4242' absent from source"
fi

# NE-HIGH-1: listenHost or "[::]"
if rg -nF 'or "[::]"' "${repo_root}/s88" --glob '*.nix' >/dev/null 2>&1; then
  echo "FAIL: NE-HIGH-1 — 'or \"[::]\"' (listenHost default) still present in source" >&2
  rg -nF 'or "[::]"' "${repo_root}/s88" --glob '*.nix' >&2
  failures=$((failures + 1))
else
  echo "PASS NE-HIGH-1: 'or \"[::]\"' absent from source"
fi

# NE-HIGH-2: family or 6 (route.family / prefix.family)
if rg -n 'family\s+or\s+6' "${repo_root}/s88" --glob '*.nix' >/dev/null 2>&1; then
  echo "FAIL: NE-HIGH-2 — 'family or 6' still present in source" >&2
  rg -n 'family\s+or\s+6' "${repo_root}/s88" --glob '*.nix' >&2
  failures=$((failures + 1))
else
  echo "PASS NE-HIGH-2: 'family or 6' absent from source"
fi

# NE-HIGH-3: name or "nebula-runtime" (service.name)
if rg -nF 'or "nebula-runtime"' "${repo_root}/s88" --glob '*.nix' >/dev/null 2>&1; then
  echo "FAIL: NE-HIGH-3 — 'or \"nebula-runtime\"' (service name default) still present in source" >&2
  rg -nF 'or "nebula-runtime"' "${repo_root}/s88" --glob '*.nix' >&2
  failures=$((failures + 1))
else
  echo "PASS NE-HIGH-3: 'or \"nebula-runtime\"' absent from source"
fi

# NE-HIGH-4: route.install or true in node-merge.nix (should be or false)
if rg -n 'install\s+or\s+true' "${repo_root}/s88/Enterprise/node-merge.nix" >/dev/null 2>&1; then
  echo "FAIL: NE-HIGH-4 — 'install or true' still present in node-merge.nix" >&2
  rg -n 'install\s+or\s+true' "${repo_root}/s88/Enterprise/node-merge.nix" >&2
  failures=$((failures + 1))
else
  echo "PASS NE-HIGH-4: 'install or true' absent from node-merge.nix"
fi

# NE-HIGH-5: allocation or "runtime"
if rg -nF 'or "runtime"' "${repo_root}/s88/Enterprise/derived-dynamic-firewall-cidrs.nix" >/dev/null 2>&1; then
  echo "FAIL: NE-HIGH-5 — 'or \"runtime\"' (prefix.allocation default) still present in derived-dynamic-firewall-cidrs.nix" >&2
  rg -nF 'or "runtime"' "${repo_root}/s88/Enterprise/derived-dynamic-firewall-cidrs.nix" >&2
  failures=$((failures + 1))
else
  echo "PASS NE-HIGH-5: 'or \"runtime\"' absent from derived-dynamic-firewall-cidrs.nix"
fi

# NE-HIGH-6: node or "lighthouse"
if rg -nF 'or "lighthouse"' "${repo_root}/s88/Enterprise/bootstrap/nixos-module/lighthouses.nix" >/dev/null 2>&1; then
  echo "FAIL: NE-HIGH-6 — 'or \"lighthouse\"' (lighthouse node default) still present in lighthouses.nix" >&2
  rg -nF 'or "lighthouse"' "${repo_root}/s88/Enterprise/bootstrap/nixos-module/lighthouses.nix" >&2
  failures=$((failures + 1))
else
  echo "PASS NE-HIGH-6: 'or \"lighthouse\"' absent from lighthouses.nix"
fi

# ============================================================
# Phase 2: Source-scan — confirm new throw diagnostics exist
# ============================================================

declare -A expected_throws=(
  ["NE-CRIT-1"]="throw \"FS-310-HDS-010-SDS-010-SMS-110: lighthouse.port required"
  ["NE-HIGH-1"]="throw \"FS-310-HDS-010-SDS-010-SMS-110: service.listenHost required"
  ["NE-HIGH-2-route"]="throw \"FS-310-HDS-010-SDS-010-SMS-110: route.family required"
  ["NE-HIGH-2-prefix"]="throw \"FS-310-HDS-010-SDS-010-SMS-110: prefix.family required"
  ["NE-HIGH-3"]="throw \"FS-310-HDS-010-SDS-010-SMS-110: service.name required"
  ["NE-HIGH-5"]="throw \"FS-310-HDS-010-SDS-010-SMS-110: prefix.allocation required"
  ["NE-HIGH-6"]="throw \"FS-310-HDS-010-SDS-010-SMS-110: lighthouse.node required"
)

for item in "${!expected_throws[@]}"; do
  pattern="${expected_throws[$item]}"
  if rg -nF "$pattern" "${repo_root}/s88" --glob '*.nix' >/dev/null 2>&1; then
    echo "PASS ${item}: throw diagnostic present — ${pattern}"
  else
    echo "FAIL: ${item} — throw diagnostic NOT found: ${pattern}" >&2
    failures=$((failures + 1))
  fi
done

# NE-HIGH-4: install or false (not a throw — opt-in boolean flip)
if rg -n 'install\s+or\s+false' "${repo_root}/s88/Enterprise/node-merge.nix" >/dev/null 2>&1; then
  echo "PASS NE-HIGH-4: 'install or false' present in node-merge.nix (opt-in boolean)"
else
  echo "FAIL: NE-HIGH-4 — 'install or false' NOT found in node-merge.nix" >&2
  failures=$((failures + 1))
fi

# ============================================================
# Phase 3: Seeded negative — nix eval confirms throw for missing lighthouse.port
# ============================================================

echo "--- seeded negative: missing lighthouse.port ---"

if nix eval --impure --no-warn-dirty --expr "
  let
    flake = builtins.getFlake (toString \"$repo_root\");
    lib = flake.inputs.nixpkgs.lib;
    planNix = import \"${repo_root}/s88/Enterprise/bootstrap/nixos-module/plan.nix\" {
      inherit lib;
      nebulaRuntimePlan = {
        overlays = {};
        nodes.test-node = {
          lighthouse = {
            # port intentionally missing — must throw
            overlayAddresses = [ \"10.0.0.0/24\" \"fd00::/64\" ];
            overlayIps = [ \"10.0.0.1\" \"fd00::1\" ];
          };
        };
      };
    };
    result = builtins.tryEval (builtins.deepSeq planNix.runtimeNodes true);
  in
    if result.success then
      throw \"FAIL: expected throw for missing lighthouse.port, but evaluation succeeded\"
    else
      true
" >/dev/null 2>&1; then
  echo "PASS seeded-negative-lighthouse-port: missing port correctly throws"
else
  echo "FAIL: seeded-negative-lighthouse-port — nix eval failed unexpectedly" >&2
  failures=$((failures + 1))
fi

# ============================================================
# Phase 4: Seeded negative — missing service.listenHost
# ============================================================

echo "--- seeded negative: missing service.listenHost ---"

if nix eval --impure --no-warn-dirty --expr "
  let
    flake = builtins.getFlake (toString \"$repo_root\");
    lib = flake.inputs.nixpkgs.lib;
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    runtimeNode = {
      service = {
        interface = \"nebula1\";
        # listenHost intentionally missing — must throw
        port = 4242;
      };
      lighthouse = {
        port = 4242;
        overlayIps = [ \"10.0.0.1\" \"fd00::1\" ];
      };
      overlayAddresses = [ \"10.0.0.0/24\" \"fd00::/64\" ];
    };
    mod = import \"${repo_root}/s88/Enterprise/runtime/nixos-module.nix\" {
      inherit lib pkgs;
      nodeName = \"test-node\";
      inherit runtimeNode;
    };
    # Force evaluation of listen.host which depends on listenHost
    listenHost = mod.services.nebula.networks.runtime.listen.host;
    result = builtins.tryEval (builtins.seq listenHost true);
  in
    if result.success then
      throw \"FAIL: expected throw for missing service.listenHost, but evaluation succeeded\"
    else
      true
" >/dev/null 2>&1; then
  echo "PASS seeded-negative-listenHost: missing listenHost correctly throws"
else
  echo "FAIL: seeded-negative-listenHost — nix eval failed unexpectedly" >&2
  failures=$((failures + 1))
fi

# ============================================================
# Report
# ============================================================
if ((failures > 0)); then
  echo "FAIL: ${failures} check(s) failed" >&2
  exit 1
fi

echo "PASS test-fs310-hds010-sds010-sms110-nebula-crit-fix"
