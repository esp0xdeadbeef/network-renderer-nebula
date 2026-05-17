#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
examples_root="${NETWORK_RENDERER_NEBULA_EXAMPLE_ROOT:-${labs_path}/examples}"

example_dirs() {
  local root="$1"

  if [[ -f "${root}/intent.nix" ]]; then
    printf '%s\n' "${root}"
  else
    find "${root}" -mindepth 2 -maxdepth 2 -type f -name intent.nix -printf '%h\n' | sort
  fi
}

check_plan_boundary() {
  local example_dir="$1"
  local plan_json="$2"

  jq -e '
    def policy_shape:
      objects
      | select(
          has("forwardPairs")
          or has("forwardRules")
          or has("forwardingIntent")
          or has("nftables")
          or has("iptables")
          or has("ip6tables")
          or has("firewall")
        );

    ([.. | policy_shape] | length) == 0
    and
    ([.nodes[]?.unsafeRoutes[]? | select(.route == "0.0.0.0/0" or .route == "::/0")] | length) == 0
  ' "${plan_json}" >/dev/null && return 0

  jq -r --arg example "${example_dir}" '
    def policy_shape:
      objects
      | select(
          has("forwardPairs")
          or has("forwardRules")
          or has("forwardingIntent")
          or has("nftables")
          or has("iptables")
          or has("ip6tables")
          or has("firewall")
        );

    ([.. | policy_shape] | length) as $policy_count
    | ([.nodes[]?.unsafeRoutes[]? | select(.route == "0.0.0.0/0" or .route == "::/0")] | length) as $default_routes
    | if $policy_count > 0 then
        "!!!! " + $example + " Nebula provider output contains "
        + ($policy_count | tostring)
        + " forwarding/firewall policy-shaped objects"
      else empty end,
      if $default_routes > 0 then
        "!!!! " + $example + " Nebula provider output contains "
        + ($default_routes | tostring)
        + " unsafe default-route exports"
      else empty end
  ' "${plan_json}" >&2

  return 1
}

[[ -d "${examples_root}" ]] || {
  echo "!!!! test-provider-boundary-no-forwarding-policy: missing examples root: ${examples_root}" >&2
  exit 1
}

ran=0
skipped=0
failed=0

while IFS= read -r example_dir; do
  [[ -n "${example_dir}" ]] || continue
  inventory_path="${example_dir}/inventory-nixos.nix"
  if [[ ! -f "${inventory_path}" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  ran=$((ran + 1))
  tmp_dir="$(mktemp -d)"

  if REPO_ROOT="${repo_root}" \
    EXAMPLE_INTENT="${example_dir}/intent.nix" \
    EXAMPLE_INVENTORY="${inventory_path}" \
    nix eval --impure --no-warn-dirty --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
      in
      import "${repo_root}/tests/nix/nebula-plan-from-inputs.nix" {
        repoRoot = builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "EXAMPLE_INTENT";
        inventoryPath = builtins.getEnv "EXAMPLE_INVENTORY";
      }
    ' >"${tmp_dir}/plan.json" 2>"${tmp_dir}/render.err"; then
    check_plan_boundary "${example_dir}" "${tmp_dir}/plan.json" || failed=1
  else
    echo "!!!! ${example_dir} Nebula provider plan render failed; boundary not verified" >&2
    sed -n '1,8p' "${tmp_dir}/render.err" | sed 's/^/!!!!   /' >&2
    failed=1
  fi

  rm -rf "${tmp_dir}"
done < <(example_dirs "${examples_root}")

if (( ran == 0 )); then
  echo "!!!! test-provider-boundary-no-forwarding-policy: no runnable examples under ${examples_root}" >&2
  exit 1
fi

if (( failed != 0 )); then
  echo "!!!! test-provider-boundary-no-forwarding-policy: PROD-UNSAFE provider-boundary violation; scanned=${ran} skipped=${skipped}" >&2
  exit 1
fi

echo "PASS test-provider-boundary-no-forwarding-policy scanned=${ran} skipped=${skipped}"
