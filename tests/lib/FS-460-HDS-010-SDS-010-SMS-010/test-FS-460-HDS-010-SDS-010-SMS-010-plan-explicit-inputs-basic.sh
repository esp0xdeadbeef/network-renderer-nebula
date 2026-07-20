#!/usr/bin/env bash
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
  in
    import "'"$repo_root"'/tests/nix/nebula-plan-from-inputs.nix" {
      repoRoot = "'"$repo_root"'";
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    }
' > "$tmp_dir/plan.json"

jq -e '
  .overlays["esp0xdeadbeef::site-a::east-west"].lighthouse.port == "4242" and
  .overlays["esp0xdeadbeef::site-c::east-west"].lighthouse.node == "c-router-lighthouse" and
  (.nodes | has("nebula-core")) and
  .nodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
  .nodes["s-router-core-nebula"].materialization.container.profile == "core-router-nebula" and
  .nodes["s-router-core-nebula"].relay.relays == [] and
  .nodes["b-router-core-nebula"].relay.relays == [] and
  .nodes["c-router-nebula-core"].relay.amRelay == false and
  .nodes["c-router-nebula-core"].materialization.container.profile == "core-router-nebula" and
  (
    .nodes["c-router-nebula-core"].dynamicFirewallCidrs
    | map(select(.sourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"))
    | length
  ) == 1
' "$tmp_dir/plan.json" >/dev/null

echo "PASS test-nebula-plan-explicit-inputs-basic"
