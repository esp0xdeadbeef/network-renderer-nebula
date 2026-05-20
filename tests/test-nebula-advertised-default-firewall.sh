#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/intent.nix"
inventory_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/inventory.nix"
plan_json="${tmp_dir}/plan.json"

nix eval --impure --no-warn-dirty --json --expr '
  import "'"${repo_root}"'/tests/nix/nebula-plan-from-inputs.nix" {
    repoRoot = "'"${repo_root}"'";
    intentPath = "'"${intent_path}"'";
    inventoryPath = "'"${inventory_path}"'";
  }
' > "${plan_json}"

jq -e '
  .nodes["hetz-router-nebula-core"] as $node
  | ($node.nebulaNetwork.settings.nebulaFirewallRules.inbound | map(.local_cidr)) as $in
  | ($node.nebulaNetwork.settings.nebulaFirewallRules.outbound | map(.local_cidr)) as $out
  | {
      ok:
        (
          ($node.advertisedUnsafeNetworks | index("::/1") != null)
          and ($node.advertisedUnsafeNetworks | index("8000::/1") != null)
          and ($node.unsafeRoutes | map(.route) | index("::/1") == null)
          and ($node.unsafeRoutes | map(.route) | index("8000::/1") == null)
          and ($in | index("::/1") != null)
          and ($in | index("8000::/1") != null)
          and ($out | index("::/1") != null)
          and ($out | index("8000::/1") != null)
        ),
      advertisedUnsafeNetworks: $node.advertisedUnsafeNetworks,
      unsafeRoutes: $node.unsafeRoutes,
      firewallDefaults: {
        inbound: ($in | map(select(. == "::/1" or . == "8000::/1"))),
        outbound: ($out | map(select(. == "::/1" or . == "8000::/1")))
      }
    }
' "${plan_json}" > "${tmp_dir}/observed.json"

if ! jq -e '.ok == true' "${tmp_dir}/observed.json" >/dev/null; then
  echo "FAIL nebula-advertised-default-firewall: Hetz exit node must firewall-allow advertised split defaults without installing them as local unsafe routes" >&2
  jq . "${tmp_dir}/observed.json" >&2
  exit 1
fi

echo "PASS nebula-advertised-default-firewall"
