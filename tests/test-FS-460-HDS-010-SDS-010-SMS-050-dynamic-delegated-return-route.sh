#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"
plan_json="${tmp_dir}/plan.json"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
  in
  import "'"${repo_root}"'/tests/nix/nebula-plan-from-inputs.nix" {
    repoRoot = "'"${repo_root}"'";
    intentPath = "'"${intent_path}"'";
    inventoryPath = "'"${inventory_path}"'";
  }
' > "${plan_json}"

jq -e '
  . as $plan
  | $plan.nodes["c-router-nebula-core"].dynamicFirewallCidrs as $site_c_firewall
  | $plan.nodes["c-router-nebula-core"].dynamicUnsafeRoutes as $site_c_dynamic_routes
  | $plan.nodes["b-router-core-nebula"].dynamicUnsafeRoutes as $branch_dynamic_routes
  | {
      ok:
        (
          (
            $site_c_firewall
            | map(select(
                .sourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"
                and .family == 6
              ))
            | length
          ) == 1
          and ($site_c_dynamic_routes | length) == 0
          and (
            $branch_dynamic_routes
            | map(select(
                .sourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"
                and .family == 6
              ))
            | length
          ) == 1
          and (
            $plan.nodes["c-router-nebula-core"].unsafeRoutes
            | map(select(.routeSourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"))
            | length
          ) == 0
        ),
      expected: {
        sourceFile: "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile",
        siteC: "dynamicFirewallCidrs",
        branch: "dynamicUnsafeRoutes",
        forbiddenHardcodedRouteSourceFile: true
      },
      observed: {
        siteCFirewall: $site_c_firewall,
        siteCDynamicUnsafeRoutes: $site_c_dynamic_routes,
        branchDynamicUnsafeRoutes: $branch_dynamic_routes,
        siteCUnsafeRouteSourceFiles:
          (
            $plan.nodes["c-router-nebula-core"].unsafeRoutes
            | map(select(.routeSourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"))
          )
      }
    }
' "${plan_json}" > "${tmp_dir}/observed.json"

if ! jq -e '.ok == true' "${tmp_dir}/observed.json" >/dev/null; then
  echo "FAIL nebula-dynamic-delegated-return-route: expected dynamic source-file authority to remain dynamic instead of becoming a hardcoded unsafe route" >&2
  jq . "${tmp_dir}/observed.json" >&2
  exit 1
fi

echo "PASS nebula-dynamic-delegated-return-route"
