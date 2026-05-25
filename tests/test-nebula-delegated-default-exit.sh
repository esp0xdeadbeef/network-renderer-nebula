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
  .nodes["b-router-core-nebula"].unsafeRoutes as $routes
  | {
      ok:
        (
          ($routes | map(select(.route == "0.0.0.0/1" and .via4 == "100.96.10.3" and .install == false)) | length) == 1
          and ($routes | map(select(.route == "128.0.0.0/1" and .via4 == "100.96.10.3" and .install == false)) | length) == 1
          and ($routes | map(select(.route == "::/1" and .via6 == "fd42:dead:beef:ee::3" and .install == false)) | length) == 1
          and ($routes | map(select(.route == "8000::/1" and .via6 == "fd42:dead:beef:ee::3" and .install == false)) | length) == 1
          and (($routes | map(.route) | index("0.0.0.0/0")) == null)
          and (($routes | map(.route) | index("::/0")) == null)
        ),
      expected: {
        node: "b-router-core-nebula",
        peerSite: "esp0xdeadbeef.site-c",
        splitRoutes: ["0.0.0.0/1", "128.0.0.0/1", "::/1", "8000::/1"],
        install: false,
        via4: "100.96.10.3",
        via6: "fd42:dead:beef:ee::3",
        forbiddenRawDefault: ["0.0.0.0/0", "::/0"]
      },
      observedUnsafeRoutes: $routes
    }
' "${plan_json}" > "${tmp_dir}/observed.json"

if ! jq -e '.ok == true' "${tmp_dir}/observed.json" >/dev/null; then
  echo "FAIL nebula-delegated-default-exit: expected example delegated IPv6 public egress to materialize as split unsafe routes via site-C overlay core" >&2
  jq . "${tmp_dir}/observed.json" >&2
  exit 1
fi

echo "PASS nebula-delegated-default-exit"
