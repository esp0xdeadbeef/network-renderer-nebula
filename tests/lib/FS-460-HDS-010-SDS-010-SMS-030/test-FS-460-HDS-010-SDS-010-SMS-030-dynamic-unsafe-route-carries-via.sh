#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-030
#
# Regression: a peer-site Nebula overlay route whose CPM `family` is the integer
# 4/6 (the canonical form the CPM emits for overlay routes) must still render a
# nebula unsafe_routes entry carrying via4/via6.  A route rendered with
# install:true but no via makes nebula refuse to start ("entry N.via in
# tun.unsafe_routes is not present"), which under systemd becomes an endless
# restart loop that pins a core.  The family match must not depend on the
# string form ("ipv4"/"ipv6").
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
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

# Every dynamic unsafe route that survives to the plan must carry a next hop.
# A route with no via4/via6 is not a usable unsafe route.
jq -e '
  [
    .nodes[]
    | (.dynamicUnsafeRoutes // [])[]
    | select((.via4 == null) and (.via6 == null))
  ] as $via_less
  | {
      ok: (($via_less | length) == 0),
      observed: $via_less,
    }
' "${plan_json}" > "${tmp_dir}/out.json"

if ! jq -e '.ok == true' "${tmp_dir}/out.json" >/dev/null; then
  echo "FAIL nebula-dynamic-unsafe-route-carries-via: dynamic unsafe route rendered without via4/via6 (nebula would fail to start):" >&2
  jq . "${tmp_dir}/out.json" >&2
  exit 1
fi

echo "PASS nebula-dynamic-unsafe-route-carries-via"
