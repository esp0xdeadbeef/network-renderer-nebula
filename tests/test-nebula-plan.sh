#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-test-three-site/intent.nix"
inventory_path="${labs_path}/examples/s-router-test-three-site/inventory-nixos.nix"

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
    .nodes["s-router-core-nebula"].unsafeRoutes
    | map(select(.route == "10.60.10.0/24" and .via4 == "100.96.10.2" and .install == true))
    | length
  ) == 1 and
  (
    .nodes["c-router-nebula-core"].unsafeRoutes
    | map(select(.route == "fd42:dead:beef:10::/64" and .via6 == "fd42:dead:beef:ec::1" and .install == true))
    | length
  ) == 1 and
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

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    system = "x86_64-linux";
    api = flake.libBySystem.${system}.renderer;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    plan = api.buildNebulaPlanFromPaths {
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
    module = api.buildNebulaBootstrapNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = plan;
      externalLighthouseReturnIpv4Cidrs = [ "10.70.10.0/24" ];
    };
  in
  {
    profileServiceType = module.systemd.services.nebula-profile-bootstrap.serviceConfig.Type;
    spec = builtins.fromJSON module.environment.etc."s-router-test/nebula-bootstrap-spec.json".text;
  }
' > "$tmp_dir/bootstrap.json"

jq -e '
  .profileServiceType == "oneshot" and
  (.spec.runtimeNodes["b-router-core-nebula"].unsafeRoutes | length) > 0 and
  (.spec.lighthouses["east-west"].unsafeNetworks | index("::/1") != null)
' "$tmp_dir/bootstrap.json" >/dev/null

echo "PASS test-nebula-plan"
