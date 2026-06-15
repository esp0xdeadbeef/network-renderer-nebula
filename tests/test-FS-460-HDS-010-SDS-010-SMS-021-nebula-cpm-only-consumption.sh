#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-021
# Construction test: Nebula Renderer CPM-Only Consumption
# Proves: Nebula renderer consumes all network data exclusively through
# CPM-mediated overlay output. No direct intent/inventory imports, no
# raw inventory tree walks, no upstream file path construction.
#
# SMS-021 is the Nebula per-renderer child of FS-310 SMS-100 (generic
# renderer CPM-only consumption). Two active seeded negatives required.
#
# Diagnostic identifiers (SMS §Module Failure Conditions):
#   DIRECT_UPSTREAM_FILE_ACCESS       — import/read of intent.nix/inventory*.nix
#   DIRECT_UPSTREAM_PATH_CONSTRUCTION — filesystem path to upstream files
#   RAW_INVENTORY_TREE_WALK           — raw inventory tree walk (e.g. inventory.overlays.*.nebula)
#   RAW_PATH_ENTRYPOINT               — flake/entrypoint accepts raw .nix file paths
#   NON_CPM_SOURCE_FLAG               — CLI flag points to non-CPM source
#   DIRECT_FORWARDING_MODEL_ACCESS    — forwarding-model access outside CPM
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/s88"

echo "--- FS-460-HDS-010-SDS-010-SMS-021: Nebula Renderer CPM-Only Consumption ---"
echo ""

# ============================================================
# Diagnostic identifiers (per SMS §Module Failure Conditions)
# ============================================================
DIAGNOSTICS=(
  "DIRECT_UPSTREAM_FILE_ACCESS"
  "DIRECT_UPSTREAM_PATH_CONSTRUCTION"
  "RAW_INVENTORY_TREE_WALK"
  "RAW_PATH_ENTRYPOINT"
  "NON_CPM_SOURCE_FLAG"
  "DIRECT_FORWARDING_MODEL_ACCESS"
)

# ============================================================
# Helper: assign diagnostic to a violation hit
# ============================================================
assign_diagnostic() {
  local content="$1"

  # Raw inventory tree walk pattern (most specific)
  if echo "${content}" | grep -qE '(inventory\.overlays\.[^.]*\.nebula|inventory\..*\.nebula[^i])'; then
    echo "RAW_INVENTORY_TREE_WALK"
    return
  fi

  # builtins.readFile of upstream source
  if echo "${content}" | grep -qE 'builtins\.(readFile|readDir|pathExists).*(intent\.nix|inventory.*\.nix|forwarding-model)'; then
    echo "DIRECT_UPSTREAM_FILE_ACCESS"
    return
  fi

  # Direct import/read of upstream files (check before path construction —
  # a path construction to intent.nix is also DIRECT_UPSTREAM_FILE_ACCESS
  # per SMS §Module Failure Conditions #1)
  if echo "${content}" | grep -qE '(intent\.nix|inventory-nixos\.nix|inventory-clab\.nix|[^a-zA-Z]inventory\.nix|forwarding-model.*\.nix)'; then
    echo "DIRECT_UPSTREAM_FILE_ACCESS"
    return
  fi

  # Path construction to upstream files (only if not already caught as file access)
  if echo "${content}" | grep -qE '(resolvedFabricRoot|resolvedExampleDir|outPath|\$\{outPath\}).*(intent|inventory)'; then
    echo "DIRECT_UPSTREAM_PATH_CONSTRUCTION"
    return
  fi

  # Default
  echo "DIRECT_UPSTREAM_FILE_ACCESS"
}

# ============================================================
# Helper: classify a hit (production path vs permitted)
# ============================================================
classify_hit() {
  local file_path="$1"
  local content="$2"

  # Strip line-number prefix from grep -n output
  local content_only="${content#*:}"

  # Skip comment-only lines
  if echo "${content_only}" | grep -qE '^\s*(#|//)'; then
    echo "COMMENT"
    return
  fi

  # Skip lines that explain the prohibition (guard assertions, throw messages)
  if echo "${content_only}" | grep -qF 'FS-460-HDS-010-SDS-010-SMS-021'; then
    echo "GUARD_ASSERTION"
    return
  fi
  if echo "${content_only}" | grep -qF 'renderers must consume'; then
    echo "GUARD_ASSERTION"
    return
  fi
  if echo "${content_only}" | grep -qF 'DIRECT_UPSTREAM_FILE_ACCESS'; then
    echo "GUARD_ASSERTION"
    return
  fi
  if echo "${content_only}" | grep -qF 'RAW_INVENTORY_TREE_WALK'; then
    echo "GUARD_ASSERTION"
    return
  fi

  echo "PRODUCTION_PATH"
}

# ============================================================
# P1: Scan s88/ for direct upstream file references
# ============================================================
echo "--- P1: Scanning for direct upstream file references ---"

# Patterns matching direct upstream file access
# We look for intent.nix, inventory*.nix, forwarding-model .nix references
# in production Nix source files (not tests, not flake.lock)
upstream_pattern='intent\.nix|inventory-nixos\.nix|inventory-clab\.nix|[^a-zA-Z]inventory\.nix|forwarding-model.*\.nix'

p1_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${upstream_pattern}" 2>/dev/null \
  || true)"

upstream_count=0
new_violations=0
known_gap_count=0

# KNOWN_GAPS for P1: pre-existing violations tracked but not yet resolved
# Format: "file_substring:content_substring"
KNOWN_GAPS_P1=(
  # Currently empty — Nebula renderer source is clean of direct upstream file access.
  # When new violations are discovered during audit, add them here.
)

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"

  case "${classification}" in
    COMMENT|GUARD_ASSERTION)
      # Permitted — not a production violation
      ;;
    PRODUCTION_PATH)
      upstream_count=$((upstream_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"

      is_known=false
      for kg in "${KNOWN_GAPS_P1[@]}"; do
        kf="${kg%%:*}"
        kc="${kg#*:}"
        if [[ "${rel_path}" == *"${kf}"* ]] && echo "${content}" | grep -qF "${kc}"; then
          is_known=true
          break
        fi
      done

      if [[ "${is_known}" == "true" ]]; then
        known_gap_count=$((known_gap_count + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
        new_violations=$((new_violations + 1))
      fi
      ;;
  esac
done <<< "${p1_hits}"

echo "P1: ${upstream_count} production-path hits (${known_gap_count} known gaps, ${new_violations} new violations)"
[[ "${new_violations}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P2: Scan for builtins.readFile of upstream source files
# ============================================================
echo "--- P2: Scanning for builtins.readFile of upstream source ---"

readfile_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE 'builtins\.(readFile|readDir|pathExists).*(intent\.nix|inventory.*\.nix|forwarding-model)' 2>/dev/null \
  || true)"

readfile_violations=0
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  echo "  NEW_VIOLATION [DIRECT_UPSTREAM_FILE_ACCESS] ${rel_path}: $(echo "${content}" | head -c 80)"
  readfile_violations=$((readfile_violations + 1))
done <<< "${readfile_hits}"

echo "P2: ${readfile_violations} builtins.readFile of upstream source violations"
[[ "${readfile_violations}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P3: Scan for raw inventory tree walks
# ============================================================
echo "--- P3: Scanning for raw inventory tree walks ---"

# Raw inventory tree walks: patterns that walk inventory tree instead of
# consuming CPM-mediated data. The Nebula renderer correctly uses
# overlayCpm.nebula / cpmData.overlays.*.nebula — these go through CPM.
# We flag patterns like inventory.overlays.<name>.nebula that bypass CPM.
treewalk_pattern='inventory\.overlays\.[^.]*\.nebula[^a-zA-Z]'

treewalk_hits="$(find "${src_dir}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${treewalk_pattern}" 2>/dev/null \
  || true)"

treewalk_violations=0
# KNOWN_GAPS for P3
KNOWN_GAPS_P3=(
  # Currently empty — no raw inventory tree walks in Nebula renderer source.
)

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"

  classification="$(classify_hit "${rel_path}" "${content}")"

  case "${classification}" in
    COMMENT|GUARD_ASSERTION)
      ;;
    PRODUCTION_PATH)
      is_known=false
      for kg in "${KNOWN_GAPS_P3[@]}"; do
        kf="${kg%%:*}"
        kc="${kg#*:}"
        if [[ "${rel_path}" == *"${kf}"* ]] && echo "${content}" | grep -qF "${kc}"; then
          is_known=true
          break
        fi
      done

      if [[ "${is_known}" != "true" ]]; then
        echo "  NEW_VIOLATION [RAW_INVENTORY_TREE_WALK] ${rel_path}: $(echo "${content}" | head -c 80)"
        treewalk_violations=$((treewalk_violations + 1))
      fi
      ;;
  esac
done <<< "${treewalk_hits}"

echo "P3: ${treewalk_violations} raw inventory tree walk violations"
[[ "${treewalk_violations}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P4: flake.nix entrypoint verification
# ============================================================
echo "--- P4: flake.nix entrypoint verification ---"

flake_nix="${repo_root}/flake.nix"
if [[ -f "${flake_nix}" ]]; then
  # Verify flake.nix does not accept --intent or --inventory raw paths
  if grep -qE -- '--intent|--inventory' "${flake_nix}" 2>/dev/null; then
    # Check if these are comments/help text, not actual parameter acceptance
    raw_flag_lines="$(grep -nE -- '--intent|--inventory' "${flake_nix}" 2>/dev/null || true)"
    echo "  WARN: flake.nix contains --intent/--inventory references — verify these are docs, not params"
    echo "  ${raw_flag_lines}"
  else
    echo "  PASS: flake.nix does not accept --intent/--inventory raw path flags"
  fi

  # Verify flake.nix imports are proper flake inputs, not raw file paths
  if grep -qE 'builtins\.(readFile|readDir)\s+.*intent\.nix|builtins\.(readFile|readDir)\s+.*inventory.*\.nix' "${flake_nix}" 2>/dev/null; then
    echo "  FAIL [RAW_PATH_ENTRYPOINT]: flake.nix reads intent/inventory via builtins.readFile"
    all_checks_passed=false
  else
    echo "  PASS: flake.nix does not read intent/inventory via builtins.readFile"
  fi

  # Verify flake.nix imports network-control-plane-model as a flake input (correct)
  if grep -q 'network-control-plane-model' "${flake_nix}" 2>/dev/null; then
    echo "  PASS: flake.nix imports network-control-plane-model as flake dependency"
  else
    echo "  WARN: flake.nix does not reference network-control-plane-model"
  fi
else
  echo "  WARN: flake.nix not found at expected path"
fi
echo ""

# ============================================================
# P5: CLI entrypoint verification
# ============================================================
echo "--- P5: CLI entrypoint verification ---"

cli_file="${repo_root}/s88/Enterprise/cli/render-node.nix"
if [[ -f "${cli_file}" ]]; then
  # Verify CLI uses --cpm flag accepting JSON, not raw .nix files
  if grep -q 'cpmPath' "${cli_file}" 2>/dev/null; then
    echo "  PASS: CLI render-node uses cpmPath (CPM JSON input)"
  else
    echo "  FAIL [RAW_PATH_ENTRYPOINT]: CLI render-node missing cpmPath parameter"
    all_checks_passed=false
  fi

  # Verify CLI reads JSON via builtins.readFile (correct for CPM JSON)
  if grep -q 'builtins\.fromJSON.*builtins\.readFile' "${cli_file}" 2>/dev/null; then
    echo "  PASS: CLI reads CPM input as JSON via builtins.readFile"
  else
    echo "  WARN: CLI does not use builtins.fromJSON (builtins.readFile ...) pattern"
  fi

  # Verify CLI rejects non-JSON input (has validation)
  if grep -q 'hasRuntimePlan\|hasControlPlane' "${cli_file}" 2>/dev/null; then
    echo "  PASS: CLI validates CPM JSON structure (hasRuntimePlan/hasControlPlane)"
  fi

  # Verify CLI does not accept raw .nix file paths
  if grep -qE '(intentPath|inventoryPath|intent\.nix|inventory.*\.nix)' "${cli_file}" 2>/dev/null; then
    cli_raw_hits="$(grep -nE '(intentPath|inventoryPath|intent\.nix|inventory.*\.nix)' "${cli_file}" 2>/dev/null || true)"
    echo "  NEW_VIOLATION [RAW_PATH_ENTRYPOINT] ${cli_file}: $(echo "${cli_raw_hits}" | head -c 120)"
    all_checks_passed=false
  else
    echo "  PASS: CLI does not accept raw .nix file paths (intentPath/inventoryPath)"
  fi
else
  echo "  WARN: CLI render-node.nix not found"
fi
echo ""

# ============================================================
# P6: Verify diagnostic identifiers exist in source
# ============================================================
echo "--- P6: Diagnostic identifier verification ---"
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
# N1: Seeded Negative — DIRECT_UPSTREAM_FILE_ACCESS
# ============================================================
echo "--- N1: Seeded Negative — DIRECT_UPSTREAM_FILE_ACCESS ---"

n1_fixture="${tmp_dir}/n1-fixture"
mkdir -p "${n1_fixture}/Enterprise"

# Create a simulated production file that directly imports intent.nix
cat > "${n1_fixture}/Enterprise/bad-intent-importer.nix" << 'NIXEOF'
{ lib, outPath }:

# FS-460-HDS-010-SDS-010-SMS-021 NEGATIVE: This file simulates a
# production code path that directly imports intent.nix from a filesystem
# path, bypassing CPM mediation. Per the SMS failure condition table #1,
# this MUST be detected as DIRECT_UPSTREAM_FILE_ACCESS.

let
  intentPath = "${outPath}/inputs/intent.nix";
  intent = import intentPath;
in
{
  tenantRoutes = intent.tenantRoutes or { };
}
NIXEOF

# Scan the fixture using the same patterns as P1
n1_scan="$(find "${n1_fixture}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${upstream_pattern}" 2>/dev/null \
  || true)"

n1_detected=false
n1_diag_found=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_class="$(classify_hit "${scan_file}" "${scan_content}")"

  if [[ "${scan_class}" == "PRODUCTION_PATH" ]]; then
    scan_diag="$(assign_diagnostic "${scan_content}")"
    echo "  N1 hit [${scan_diag}] ${scan_file}: $(echo "${scan_content}" | head -c 80)"

    if [[ "${scan_diag}" == "DIRECT_UPSTREAM_FILE_ACCESS" ]]; then
      n1_diag_found=true
    fi
    if echo "${scan_content}" | grep -qE 'intent\.nix'; then
      n1_detected=true
    fi
  fi
done <<< "${n1_scan}"

if [[ "${n1_detected}" == "true" ]]; then
  echo "  PASS: N1 violation detected (direct intent.nix reference)"
else
  echo "  FAIL: N1 violation NOT detected — scanner may miss direct intent.nix references"
  all_checks_passed=false
fi

if [[ "${n1_diag_found}" == "true" ]]; then
  echo "  PASS: N1 diagnostic DIRECT_UPSTREAM_FILE_ACCESS assigned correctly"
else
  echo "  FAIL: N1 diagnostic DIRECT_UPSTREAM_FILE_ACCESS not assigned"
  all_checks_passed=false
fi

# Recovery: remove the violation and verify clean scan
rm "${n1_fixture}/Enterprise/bad-intent-importer.nix"
n1_clean_scan="$(find "${n1_fixture}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${upstream_pattern}" 2>/dev/null \
  || true)"
if [[ -z "${n1_clean_scan}" ]]; then
  echo "  PASS: N1 recovery — clean fixture has no violations"
else
  echo "  FAIL: N1 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# N2: Seeded Negative — RAW_INVENTORY_TREE_WALK
# ============================================================
echo "--- N2: Seeded Negative — RAW_INVENTORY_TREE_WALK ---"

n2_fixture="${tmp_dir}/n2-fixture"
mkdir -p "${n2_fixture}/Enterprise"

# Create a simulated production file that walks raw inventory tree
cat > "${n2_fixture}/Enterprise/bad-tree-walker.nix" << 'NIXEOF'
{ lib, inventory }:

# FS-460-HDS-010-SDS-010-SMS-021 NEGATIVE: This file simulates a
# production code path that walks the raw inventory tree to find Nebula
# realization data (inventory.overlays.east-west.nebula), bypassing
# CPM-mediated data. Per the SMS failure condition table #3, this MUST
# be detected as RAW_INVENTORY_TREE_WALK.

let
  # Raw inventory tree walk — sms-021 violation
  nebulaData = inventory.overlays.east-west.nebula or { };
  lighthouseEndpoint = nebulaData.lighthouse.endpoint or null;
in
{
  inherit lighthouseEndpoint;
}
NIXEOF

# Scan the fixture using the same patterns as P3
n2_scan="$(find "${n2_fixture}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${treewalk_pattern}" 2>/dev/null \
  || true)"

n2_detected=false
n2_diag_found=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_class="$(classify_hit "${scan_file}" "${scan_content}")"

  if [[ "${scan_class}" == "PRODUCTION_PATH" ]]; then
    scan_diag="$(assign_diagnostic "${scan_content}")"
    echo "  N2 hit [${scan_diag}] ${scan_file}: $(echo "${scan_content}" | head -c 80)"

    if [[ "${scan_diag}" == "RAW_INVENTORY_TREE_WALK" ]]; then
      n2_diag_found=true
    fi
    if echo "${scan_content}" | grep -qE 'inventory\.overlays\..*\.nebula'; then
      n2_detected=true
    fi
  fi
done <<< "${n2_scan}"

if [[ "${n2_detected}" == "true" ]]; then
  echo "  PASS: N2 violation detected (raw inventory tree walk: inventory.overlays.*.nebula)"
else
  echo "  FAIL: N2 violation NOT detected — scanner may miss raw inventory tree walks"
  all_checks_passed=false
fi

if [[ "${n2_diag_found}" == "true" ]]; then
  echo "  PASS: N2 diagnostic RAW_INVENTORY_TREE_WALK assigned correctly"
else
  echo "  FAIL: N2 diagnostic RAW_INVENTORY_TREE_WALK not assigned"
  all_checks_passed=false
fi

# Recovery: remove the violation and verify clean scan
rm "${n2_fixture}/Enterprise/bad-tree-walker.nix"
n2_clean_scan="$(find "${n2_fixture}" -name '*.nix' -print0 2>/dev/null \
  | xargs -0 grep -nE "${treewalk_pattern}" 2>/dev/null \
  || true)"
if [[ -z "${n2_clean_scan}" ]]; then
  echo "  PASS: N2 recovery — clean fixture has no violations"
else
  echo "  FAIL: N2 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# Report
# ============================================================
echo "============================================================"
echo "FS-460-HDS-010-SDS-010-SMS-021: Nebula Renderer CPM-Only Consumption"
echo "============================================================"
echo "P1 source scan: $( [[ "${new_violations}" -eq 0 ]] && echo 'PASS' || echo 'FAIL' ) (${upstream_count} hits, ${known_gap_count} known gaps, ${new_violations} new)"
echo "P2 readFile scan: $( [[ "${readfile_violations}" -eq 0 ]] && echo 'PASS' || echo 'FAIL' ) (${readfile_violations} violations)"
echo "P3 tree walk scan: $( [[ "${treewalk_violations}" -eq 0 ]] && echo 'PASS' || echo 'FAIL' ) (${treewalk_violations} violations)"
echo "P4 flake.nix verification: done"
echo "P5 CLI verification: done"
echo "P6 diagnostics: ${diag_present}/${#DIAGNOSTICS[@]} in source"
echo "N1: DIRECT_UPSTREAM_FILE_ACCESS — $( [[ "${n1_detected}" == "true" && "${n1_diag_found}" == "true" ]] && echo 'PASS (detected and recovered)' || echo 'FAIL' )"
echo "N2: RAW_INVENTORY_TREE_WALK — $( [[ "${n2_detected}" == "true" && "${n2_diag_found}" == "true" ]] && echo 'PASS (detected and recovered)' || echo 'FAIL' )"

if [[ "${all_checks_passed}" == "true" ]]; then
  echo ""
  echo "RESULT: PASS — Nebula renderer CPM-only consumption contract verified"
  exit 0
else
  echo ""
  echo "RESULT: FAIL — violations found"
  exit 1
fi
