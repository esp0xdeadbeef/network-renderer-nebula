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
  .nodes["c-router-nebula-core"].unsafeRoutes
  | map(select(
      .routeSourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"
      and .via6 == "fd42:dead:beef:ee::2"
      and .install == true
    ))
  | length == 1
' "${plan_json}" >/dev/null || {
  echo "FAIL nebula-dynamic-delegated-return-route: expected c-router-nebula-core to carry the branch hostile delegated runtime IPv6 prefix back to b-router-core-nebula via Nebula." >&2
  echo "Remove this failure only after network-renderer-nebula renders a dynamic unsafe route from the explicit CPM external-validation delegated prefix source instead of relying on network-renderer-nixos to install an on-link overlay-west route." >&2
  jq '.nodes["c-router-nebula-core"].unsafeRoutes' "${plan_json}" >&2
  exit 1
}

echo "PASS nebula-dynamic-delegated-return-route"
