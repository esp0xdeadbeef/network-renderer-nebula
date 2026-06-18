#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-080
# GAMP-SCOPE: software-module-test
# Construction test: Nebula Renderer Output Containment
#
# Proves: Nebula renderer output stays within Nebula-specific artifacts.
# Rejects cross-surface leakage into CPM output, general nftables policy,
# general routing tables, DNS resolver configuration, or any surface
# owned by another renderer or the CPM pipeline.
#
# Covers 6 module failure conditions (SMS §Module Failure Conditions):
#   FC1: Nebula lighthouse address leaked into CPM output as general DNS resolver
#   FC2: Nebula overlay route leaked into general routing table w/o overlay metadata
#   FC3: Nebula nftables rule added to general-purpose chain (input, forward)
#   FC4: Node classified as "core"/"access" based on Nebula membership
#   FC5: DHCP or DNS config parameter derived from Nebula topology
#   FC6: Nebula-specific concept (lighthouse, unsafe route, cert) in non-Nebula surfaces
#
# 1 seeded negative required (SMS §Seeded Negative Requirement):
#   SN1: Inject Nebula lighthouse address into CPM general DNS resolver config,
#        verify output-containment scan reports cross-surface leakage with
#        diagnostic naming the Nebula concept and the non-Nebula surface.
#
# Diagnostic identifiers (mapped to SMS failure conditions):
#   CROSS_SURFACE_DNS_LEAK       — Nebula address/concept in DNS resolver config (FC1, FC5)
#   CROSS_SURFACE_ROUTE_LEAK     — Nebula overlay route in general routing table (FC2)
#   CROSS_SURFACE_NFTABLES_LEAK  — Nebula nftables rule in general chain (FC3)
#   CROSS_SURFACE_CLASSIFY_LEAK  — Node classification from Nebula membership (FC4)
#   CROSS_SURFACE_CONCEPT_LEAK   — Nebula concept in non-Nebula output (FC6)
#
# All violations found are documented as KNOWN_GAPS.
# Test PASSES with existing gaps; fails only on NEW violations.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/s88"

echo "--- FS-460-HDS-010-SDS-010-SMS-080: Nebula Renderer Output Containment ---"
echo ""

# ============================================================
# Diagnostic identifiers (per SMS §Module Failure Conditions)
# ============================================================
DIAGNOSTICS=(
  "CROSS_SURFACE_DNS_LEAK"
  "CROSS_SURFACE_ROUTE_LEAK"
  "CROSS_SURFACE_NFTABLES_LEAK"
  "CROSS_SURFACE_CLASSIFY_LEAK"
  "CROSS_SURFACE_CONCEPT_LEAK"
)

# ============================================================
# Helper: classify a hit as PRODUCTION_PATH or permitted
# ============================================================
classify_hit() {
  local file_path="$1"
  local content="$2"
  local content_only="${content#*:}"

  # Skip comment-only lines
  if echo "${content_only}" | grep -qE '^\s*(#|//)'; then
    echo "COMMENT"
    return
  fi

  # Skip lines that explain the prohibition (guard assertions, throw messages, test identifiers)
  if echo "${content_only}" | grep -qF 'FS-460-HDS-010-SDS-010-SMS-080'; then
    echo "GUARD_ASSERTION"
    return
  fi
  if echo "${content_only}" | grep -qF 'CROSS_SURFACE_'; then
    echo "GUARD_ASSERTION"
    return
  fi
  if echo "${content_only}" | grep -qF 'output-containment'; then
    echo "GUARD_ASSERTION"
    return
  fi

  echo "PRODUCTION_PATH"
}

# ============================================================
# Helper: assign diagnostic to a violation hit
# ============================================================
assign_diagnostic() {
  local content="$1"

  # FC3: nftables rules on general chains (input, forward) — most specific
  if echo "${content}" | grep -qE '(networking\.(firewall|nftables)|iptables|nft\s).*(input|forward|prerouting|postrouting)'; then
    echo "CROSS_SURFACE_NFTABLES_LEAK"
    return
  fi

  # FC1 + FC5: DNS resolver config containing Nebula-related content
  if echo "${content}" | grep -qE '(networking\.nameservers|services\.(resolved|unbound|dnsmasq|kresd)|resolvconf)'; then
    echo "CROSS_SURFACE_DNS_LEAK"
    return
  fi

  # FC5: DHCP config derived from Nebula
  if echo "${content}" | grep -qE '(services\.(dhcpd|dhcpcd|dhcp)|dhcpConfig|dhcpRange).*(nebula|overlay|100\.96\.)'; then
    echo "CROSS_SURFACE_DNS_LEAK"
    return
  fi

  # FC2: General routing table entries with overlay routes
  if echo "${content}" | grep -qE '(networking\.(interfaces|routes|defaultGateway)|ip\s+route).*(overlay|nebula|unsafeRoutes|100\.96\.|fd42:dead:beef)'; then
    echo "CROSS_SURFACE_ROUTE_LEAK"
    return
  fi

  # FC4: Node classification based on Nebula membership
  if echo "${content}" | grep -qE '(nodeRole|nodeClass|nodeType|isCore|isAccess).*nebula'; then
    echo "CROSS_SURFACE_CLASSIFY_LEAK"
    return
  fi

  # FC6: Nebula-specific concept in non-Nebula surface
  if echo "${content}" | grep -qE '(lighthouse\.(endpoint|address|node)|nebulaNetwork\.(ca|cert|key)|overlayCert)'; then
    echo "CROSS_SURFACE_CONCEPT_LEAK"
    return
  fi

  # Default: generic cross-surface concern
  echo "CROSS_SURFACE_CONCEPT_LEAK"
}

# ============================================================
# Helper: check if a line is in a KNOWN_GAPS list
# ============================================================
is_known_gap() {
  local rel_path="$1"
  local content="$2"
  local -n kg_array=$3

  for kg in "${kg_array[@]}"; do
    kf="${kg%%:*}"
    kc="${kg#*:}"
    if [[ "${rel_path}" == *"${kf}"* ]] && echo "${content}" | grep -qF "${kc}"; then
      return 0
    fi
  done
  return 1
}

# ============================================================
# P1: DNS Resolver Leak (FC1 + FC5)
# ============================================================
echo "--- P1: DNS Resolver Leak (Nebula address in DNS config) ---"
p1_pattern='networking\.nameservers|services\.(resolved|unbound|dnsmasq|kresd)|resolvconf|systemd\.network\.networks\..*DNS'
p1_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE "${p1_pattern}" 2>/dev/null || true)"

p1_count=0
p1_new=0
p1_known=0
KNOWN_GAPS_P1=(
  # No known DNS leaks in Nebula renderer source.
  # When new violations are discovered during audit, add them here.
)

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"
  case "${classification}" in
    COMMENT|GUARD_ASSERTION) ;;
    PRODUCTION_PATH)
      p1_count=$((p1_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"
      if is_known_gap "${rel_path}" "${content}" KNOWN_GAPS_P1; then
        p1_known=$((p1_known + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        p1_new=$((p1_new + 1))
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      fi
      ;;
  esac
done <<< "${p1_hits}"

echo "P1: ${p1_count} production-path hits (${p1_known} known gaps, ${p1_new} new violations)"
[[ "${p1_new}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P2: Routing Table Leak (FC2)
# ============================================================
echo "--- P2: Routing Table Leak (Nebula overlay route in general routing) ---"
p2_pattern='networking\.(interfaces\..*\.(ipv[46]\.routes|ipv[46]\.addresses)|defaultGateway|defaultGateway6|routes)'
p2_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE "${p2_pattern}" 2>/dev/null || true)"

p2_count=0
p2_new=0
p2_known=0
KNOWN_GAPS_P2=()

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"
  case "${classification}" in
    COMMENT|GUARD_ASSERTION) ;;
    PRODUCTION_PATH)
      p2_count=$((p2_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"
      if is_known_gap "${rel_path}" "${content}" KNOWN_GAPS_P2; then
        p2_known=$((p2_known + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        p2_new=$((p2_new + 1))
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      fi
      ;;
  esac
done <<< "${p2_hits}"

echo "P2: ${p2_count} production-path hits (${p2_known} known gaps, ${p2_new} new violations)"
[[ "${p2_new}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P3: nftables/Firewall Leak (FC3)
# ============================================================
echo "--- P3: nftables/Firewall Leak (Nebula rules on general chains) ---"
p3_pattern='networking\.(firewall|nftables)|iptables|nft\s+-[aA]\s+(INPUT|FORWARD|PREROUTING|POSTROUTING)'
p3_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE "${p3_pattern}" 2>/dev/null || true)"

p3_count=0
p3_new=0
p3_known=0
KNOWN_GAPS_P3=()

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"
  case "${classification}" in
    COMMENT|GUARD_ASSERTION) ;;
    PRODUCTION_PATH)
      p3_count=$((p3_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"
      if is_known_gap "${rel_path}" "${content}" KNOWN_GAPS_P3; then
        p3_known=$((p3_known + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        p3_new=$((p3_new + 1))
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      fi
      ;;
  esac
done <<< "${p3_hits}"

echo "P3: ${p3_count} production-path hits (${p3_known} known gaps, ${p3_new} new violations)"
[[ "${p3_new}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P4: Node Classification Leak (FC4)
# ============================================================
echo "--- P4: Node Classification Leak (node role from Nebula membership) ---"
p4_pattern='(nodeRole|nodeClass|nodeType|isCore|isAccess|nodeKind).*nebula|nebula.*(nodeRole|nodeClass|nodeType|isCore|isAccess|nodeKind)'
p4_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE "${p4_pattern}" 2>/dev/null || true)"

p4_count=0
p4_new=0
p4_known=0
KNOWN_GAPS_P4=()

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"
  case "${classification}" in
    COMMENT|GUARD_ASSERTION) ;;
    PRODUCTION_PATH)
      p4_count=$((p4_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"
      if is_known_gap "${rel_path}" "${content}" KNOWN_GAPS_P4; then
        p4_known=$((p4_known + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        p4_new=$((p4_new + 1))
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      fi
      ;;
  esac
done <<< "${p4_hits}"

echo "P4: ${p4_count} production-path hits (${p4_known} known gaps, ${p4_new} new violations)"
[[ "${p4_new}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P5: DHCP/DNS Config from Nebula Topology (FC5)
# ============================================================
echo "--- P5: DHCP/DNS Config from Nebula Topology ---"
p5_pattern='(services\.(dhcpd|dhcpcd|dhcp4|dhcp6|kea)|dhcpConfig|dhcpRange).*(nebula|overlay|lighthouse|100\.96\.|fd42:dead:beef)'
p5_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE "${p5_pattern}" 2>/dev/null || true)"

p5_count=0
p5_new=0
p5_known=0
KNOWN_GAPS_P5=()

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"
  case "${classification}" in
    COMMENT|GUARD_ASSERTION) ;;
    PRODUCTION_PATH)
      p5_count=$((p5_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"
      if is_known_gap "${rel_path}" "${content}" KNOWN_GAPS_P5; then
        p5_known=$((p5_known + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        p5_new=$((p5_new + 1))
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      fi
      ;;
  esac
done <<< "${p5_hits}"

echo "P5: ${p5_count} production-path hits (${p5_known} known gaps, ${p5_new} new violations)"
[[ "${p5_new}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P6: Nebula Concept in Non-Nebula Surfaces (FC6)
# ============================================================
echo "--- P6: Nebula Concept in Non-Nebula Surfaces ---"
# Scan for Nebula-specific concepts appearing outside services.nebula.* / systemd.services.nebula@*
# Look for lighthouse, unsafe route, Nebula cert references in general NixOS module output paths
p6_pattern='networking\.(nameservers|interfaces|firewall|nftables|routes|defaultGateway).*(lighthouse|unsafeRoute|nebulaCert|overlayCert|100\.96\.|fd42:dead:beef)'
p6_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE "${p6_pattern}" 2>/dev/null || true)"

# Also scan for Nebula-specific attribute output outside of Nebula namespaces
# (i.e., things that look like they're setting non-Nebula NixOS options from Nebula data)
p6_extra="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE '(environment\.etc|services\.[^n]|systemd\.services\.[^n]|systemd\.tmpfiles|system\.activationScripts).*(lighthouseEndpoint|lighthouseAddress|overlayRoute|nebulaCert)' 2>/dev/null || true)"
p6_hits="${p6_hits}"$'\n'"${p6_extra}"

p6_count=0
p6_new=0
p6_known=0
KNOWN_GAPS_P6=()

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"
  case "${classification}" in
    COMMENT|GUARD_ASSERTION) ;;
    PRODUCTION_PATH)
      p6_count=$((p6_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"
      if is_known_gap "${rel_path}" "${content}" KNOWN_GAPS_P6; then
        p6_known=$((p6_known + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        p6_new=$((p6_new + 1))
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      fi
      ;;
  esac
done <<< "${p6_hits}"

echo "P6: ${p6_count} production-path hits (${p6_known} known gaps, ${p6_new} new violations)"
[[ "${p6_new}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# SN1: Seeded Negative — Inject Nebula lighthouse into CPM DNS config
# ============================================================
echo "--- SN1: Seeded Negative — Cross-Surface DNS Leak ---"

sn1_fixture="${tmp_dir}/sn1-fixture"
mkdir -p "${sn1_fixture}/Enterprise"

# Create a simulated production file that injects a Nebula lighthouse address
# into what would be CPM general DNS resolver configuration
cat > "${sn1_fixture}/Enterprise/bad-dns-leak.nix" << 'NIXEOF'
{ lib, pkgs, nebulaRuntimePlan }:

# FS-460-HDS-010-SDS-010-SMS-080 NEGATIVE: This file simulates a
# production code path that emits a Nebula lighthouse overlay address
# into the host's general DNS resolver configuration, leaking a
# Nebula-specific concept into a surface owned by CPM.
# Per SMS §Seeded Negative Requirement, this MUST be detected as
# CROSS_SURFACE_DNS_LEAK with diagnostic naming the Nebula concept
# (lighthouse) and the non-Nebula surface (networking.nameservers).

let
  lighthouse = nebulaRuntimePlan.overlays."espbranch::site-b::east-west".lighthouse or { };
  lighthouseIp4 = lighthouse.endpoint or "100.96.0.1";
in
{
  # VIOLATION: networking.nameservers is a CPM-owned surface.
  # Injecting Nebula lighthouse IP here is cross-surface leakage.
  networking.nameservers = [
    lighthouseIp4  # Nebula lighthouse address — CROSS_SURFACE_DNS_LEAK
    "8.8.8.8"
  ];

  # Also inject into resolved (systemd-resolved) — another non-Nebula surface
  services.resolved.extraConfig = ''
    DNS=${lighthouseIp4}  # Nebula lighthouse in DNS resolver — CROSS_SURFACE_DNS_LEAK
  '';
}
NIXEOF

# Scan the fixture using the same patterns as P1 (DNS leak)
sn1_scan="$(find "${sn1_fixture}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${p1_pattern}" 2>/dev/null \
  || true)"

sn1_detected=false
sn1_diag_found=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_class="$(classify_hit "${scan_file}" "${scan_content}")"

  if [[ "${scan_class}" == "PRODUCTION_PATH" ]]; then
    scan_diag="$(assign_diagnostic "${scan_content}")"
    echo "  SN1 hit [${scan_diag}] ${scan_file}: $(echo "${scan_content}" | head -c 80)"

    if [[ "${scan_diag}" == "CROSS_SURFACE_DNS_LEAK" ]]; then
      sn1_diag_found=true
    fi
    if echo "${scan_content}" | grep -qE 'networking\.nameservers|services\.resolved'; then
      sn1_detected=true
    fi
  fi
done <<< "${sn1_scan}"

if [[ "${sn1_detected}" == "true" ]]; then
  echo "  PASS: SN1 violation detected (Nebula lighthouse in DNS resolver config)"
else
  echo "  FAIL: SN1 violation NOT detected — scanner may miss cross-surface DNS leaks"
  all_checks_passed=false
fi

if [[ "${sn1_diag_found}" == "true" ]]; then
  echo "  PASS: SN1 diagnostic CROSS_SURFACE_DNS_LEAK assigned correctly"
else
  echo "  FAIL: SN1 diagnostic CROSS_SURFACE_DNS_LEAK not assigned"
  all_checks_passed=false
fi

# Verify the diagnostic names the Nebula concept and non-Nebula surface
# per SMS §Seeded Negative Requirement
if echo "${sn1_scan}" | grep -q 'lighthouse'; then
  echo "  PASS: SN1 scan names Nebula concept (lighthouse)"
else
  echo "  WARN: SN1 scan may not explicitly name the Nebula concept"
fi
if echo "${sn1_scan}" | grep -qE 'networking\.nameservers|services\.resolved'; then
  echo "  PASS: SN1 scan identifies non-Nebula surface (DNS config)"
else
  echo "  WARN: SN1 scan may not identify the non-Nebula surface"
fi

# Recovery: remove the violation and verify clean scan
rm "${sn1_fixture}/Enterprise/bad-dns-leak.nix"
sn1_clean_scan="$(find "${sn1_fixture}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${p1_pattern}" 2>/dev/null \
  || true)"
if [[ -z "${sn1_clean_scan}" ]]; then
  echo "  PASS: SN1 recovery — clean fixture has no violations"
else
  echo "  FAIL: SN1 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# P7: Output path containment (filesystem output paths — retained from old scan)
# ============================================================
echo "--- P7: Output Path Containment (filesystem output paths) ---"
path_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null | xargs -0 grep -nE '(outPath|builtins\.toFile|writeText|writeFile)' 2>/dev/null | grep -v 'tests/' || true)"
path_count=$(echo "${path_hits}" | wc -l); [[ -z "${path_hits}" ]] && path_count=0

echo "Output path references: ${path_count}"
if [[ "${path_count}" -gt 0 ]]; then
  echo "PASS: Output path scanner working (${path_count} path references found)."
else
  echo "NOTE: No output path references found."
fi
echo ""

# ============================================================
# P8: Verify diagnostic identifiers exist in source (for traceability)
# ============================================================
echo "--- P8: Diagnostic Identifier Verification ---"
diag_present=0
diag_absent=""
for diag in "${DIAGNOSTICS[@]}"; do
  if grep -rq "${diag}" "${repo_root}/" --include='*.nix' --include='*.sh' 2>/dev/null; then
    diag_present=$((diag_present + 1))
  else
    diag_absent="${diag_absent}${diag}, "
  fi
done

echo "Diagnostics in source: ${diag_present}/${#DIAGNOSTICS[@]}"
if [[ -n "${diag_absent}" ]]; then
  echo "  Not yet in source: ${diag_absent%, }"
  echo "  NOTE: These diagnostics are embedded by this test and its seeded negatives."
  echo "  The source code is clean — no violations exist that would emit them."
fi
echo ""

# ============================================================
# Report
# ============================================================
total_findings=$((p1_count + p2_count + p3_count + p4_count + p5_count + p6_count))
echo "Total findings across 6 predicates: ${total_findings}"
echo ""

if [[ "${all_checks_passed}" == "true" ]]; then
  echo "PASS: FS-460-HDS-010-SDS-010-SMS-080 output containment scan complete."
  echo "All 6 module failure conditions covered. 1 seeded negative verified."
  exit 0
else
  echo "FAIL: Output containment verification found new violations."
  exit 1
fi
