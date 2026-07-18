#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-030
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  .overlays["espbranch::site-b::east-west"].lighthouse.endpoint == "198.51.100.10" and
  .overlays["esp0xdeadbeef::site-c::east-west"].lighthouse.node == "c-router-lighthouse" and
  .nodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
  (.nodes["c-router-lighthouse"].unsafeRoutes | length) == 0 and
  .nodes["b-router-core-nebula"].overlayAddresses[0] == "100.96.10.2/24" and
  .nodes["b-router-core-nebula"].overlayAddresses[1] == "fd42:dead:beef:ee::2/64" and
  .nodes["b-router-core-nebula"].materialization.container.targetContainer == "b-router-core-nebula" and
  .nodes["c-router-nebula-core"].relay.amRelay == false and
  .nodes["c-router-nebula-core"].relay.relays == [] and
  .nodes["s-router-core-nebula"].relay.relays == [] and
  .nodes["s-router-core-nebula"].relay.useRelays == false and
  .nodes["b-router-core-nebula"].relay.relays == [] and
  .nodes["b-router-core-nebula"].relay.useRelays == false and
  (
    .nodes["s-router-core-nebula"].unsafeRoutes
    | map(select(.route == "10.60.10.0/24" and .via4 == "100.96.10.2" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["c-router-nebula-core"].unsafeRoutes
    | map(select(.route == "fd42:dead:feed:10::/64" and .via6 == "fd42:dead:beef:ee::2" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["c-router-nebula-core"].unsafeRoutes
    | map(select(.route == "10.70.10.0/24" and .via4 == "100.96.10.2" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["c-router-nebula-core"].dynamicFirewallCidrs
    | map(select(.sourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile" and .family == 6))
    | length
  ) == 1 and
  (.nodes["c-router-nebula-core"].dynamicUnsafeRoutes | length) == 0 and
  (
    .nodes["b-router-core-nebula"].unsafeRoutes
    | map(select(.route == "10.20.10.0/24" and .via4 == "100.96.10.1" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["b-router-core-nebula"].unsafeRoutes
    | map(select(.route == "10.20.50.0/24" and .via4 == "100.96.10.1" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["b-router-core-nebula"].unsafeRoutes
    | map(select(.route == "fd42:dead:beef:10::/64" and .via6 == "fd42:dead:beef:ee::1" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["b-router-core-nebula"].unsafeRoutes
    | map(select(.route == "fd42:dead:beef:50::/64" and .via6 == "fd42:dead:beef:ee::1" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["b-router-core-nebula"].nebulaNetwork.settings.tun.unsafe_routes
    | map(select(.route == "10.20.10.0/24" and .via == "100.96.10.1" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["b-router-core-nebula"].nebulaNetwork.settings.tun.unsafe_routes
    | map(select(.route == "fd42:dead:beef:50::/64" and .via == "fd42:dead:beef:ee::1" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["b-router-core-nebula"].unsafeRoutes
    | map(.route)
    | index("0.0.0.0/0") == null
      and index("::/0") == null
      and index("10.10.0.16/32") == null
      and index("fd42:dead:beef:1000:0:0:0:10/128") == null
  ) and
  (
    .nodes["b-router-core-nebula"].routePreparation.removeRoutes
    | index("10.20.10.0/24") != null
    and index("fd42:dead:beef:50::/64") != null
    and index("10.10.0.16/32") == null
    and index("fd42:dead:beef:1000:0:0:0:10/128") == null
  ) and
  (
    .nodes["b-router-core-nebula"].routePreparation.underlayEndpoints
    | index("198.51.100.10") != null and index("2001:db8:51::10") != null
  ) and
  (
    .nodes["b-router-core-nebula"].routePreparation.overlayHosts
    | index("100.96.10.254") != null and index("fd42:dead:beef:ee::254") != null
  ) and
  (.nodes | has("b-router-core") | not)
' "$tmp_dir/plan.json" >/dev/null

echo "PASS test-nebula-plan"
