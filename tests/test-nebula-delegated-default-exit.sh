#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/intent.nix"
inventory_path="${tmp_dir}/inventory.nix"
plan_json="${tmp_dir}/plan.json"

printf 'import "%s/labs/lab-s-sigma/s-router-test-three-site/getResolvedInventory.nix" { renderer = "nixos"; }\n' "${labs_path}" > "${inventory_path}"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
  in
  api.buildNebulaPlanFromPaths {
    intentPath = "'"${intent_path}"'";
    inventoryPath = "'"${inventory_path}"'";
  }
' > "${plan_json}"

jq -e '
  .nodes["b-router-core-nebula"].unsafeRoutes as $routes
  | (
      $routes
      | map(select(.route == "::/1" and .via6 == "fd42:dead:beef:ee::3" and .install == true))
      | length
    ) == 1
  and (
      $routes
      | map(select(.route == "8000::/1" and .via6 == "fd42:dead:beef:ee::3" and .install == true))
      | length
    ) == 1
  and (
      $routes
      | map(.route)
      | index("::/0") == null
    )
' "${plan_json}" >/dev/null || {
  echo "FAIL nebula-delegated-default-exit: expected lab-sigma b-router-core-nebula delegated IPv6 public egress to materialize as split ::/1 and 8000::/1 unsafe routes via site-C overlay core, not raw ::/0. Remove this error only after explicit CPM delegated-public-egress defaults produce Nebula default-exit routes and live hostile IPv6 internet no longer dies at b-router-core-nebula." >&2
  jq '.nodes["b-router-core-nebula"].unsafeRoutes' "${plan_json}" >&2
  exit 1
}

echo "PASS nebula-delegated-default-exit"
