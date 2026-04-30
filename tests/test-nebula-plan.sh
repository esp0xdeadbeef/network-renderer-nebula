#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

intent_path="/home/deadbeef/github/network-labs/examples/s-router-test-three-site/intent.nix"
inventory_path="/home/deadbeef/github/network-labs/examples/s-router-test-three-site/inventory-nixos.nix"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
  in
  api.buildNebulaPlanFromPaths {
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    }
' > "$tmp_dir/plan.json"

jq -e '
  .overlays["espbranch::site-b::east-west"].lighthouse.endpoint == "46.224.173.254" and
  .nodes["b-router-core-nebula"].overlayAddresses[0] == "100.96.10.2/24" and
  .nodes["b-router-core-nebula"].overlayAddresses[1] == "fd42:dead:beef:ee::2/64" and
  .nodes["b-router-core-nebula"].materialization.container.targetContainer == "b-router-core-nebula" and
  (
    .nodes["b-router-core-nebula"].unsafeRoutes
    | map(select((.route == "::/1" or .route == "8000::/1") and .install == true))
    | length
  ) == 2 and
  (
    .nodes["b-router-core-nebula"].routePreparation.removeRoutes
    | index("::/1") != null and index("8000::/1") != null
  ) and
  (
    .nodes["b-router-core-nebula"].routePreparation.underlayEndpoints
    | index("46.224.173.254") != null and index("2a01:4f8:c013:628b::1") != null
  ) and
  (
    .nodes["b-router-core-nebula"].routePreparation.overlayHosts
    | index("100.96.10.254") != null and index("fd42:dead:beef:ee::254") != null
  ) and
  (.nodes | has("b-router-core") | not)
' "$tmp_dir/plan.json" >/dev/null

echo "PASS test-nebula-plan"
