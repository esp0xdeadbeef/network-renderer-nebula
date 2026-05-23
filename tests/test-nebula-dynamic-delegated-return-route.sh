#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
inventory_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix"
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
  .nodes["c-router-nebula-core"].unsafeRoutes as $routes
  | {
      ok:
        (
          $routes
          | map(select(
              .routeSourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"
              and .via6 == "fd42:dead:beef:ee::2"
              and .install == true
            ))
          | length
        ) == 1,
      expected: {
        node: "c-router-nebula-core",
        dynamicRouteSourceFile: "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile",
        via6: "fd42:dead:beef:ee::2"
      },
      observedUnsafeRoutes: $routes
    }
' "${plan_json}" > "${tmp_dir}/observed.json"

if ! jq -e '.ok == true' "${tmp_dir}/observed.json" >/dev/null; then
  echo "FAIL nebula-dynamic-delegated-return-route: expected example site-C Nebula core to carry branch hostile delegated runtime IPv6 prefix back to branch Nebula core" >&2
  jq . "${tmp_dir}/observed.json" >&2
  exit 1
fi

echo "PASS nebula-dynamic-delegated-return-route"
