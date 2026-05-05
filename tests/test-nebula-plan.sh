#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
inventory_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix"

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
	  .overlays["espbranch::site-b::east-west"].lighthouse.endpoint == "198.51.100.10" and
	  .overlays["esp0xdeadbeef::site-c::east-west"].lighthouse.node == "c-router-lighthouse" and
	  .nodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
	  (.nodes["c-router-lighthouse"].unsafeRoutes | length) == 0 and
	  .nodes["b-router-core-nebula"].overlayAddresses[0] == "100.96.10.2/24" and
  .nodes["b-router-core-nebula"].overlayAddresses[1] == "fd42:dead:beef:ee::2/64" and
  .nodes["b-router-core-nebula"].materialization.container.targetContainer == "b-router-core-nebula" and
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
	    .nodes["c-router-nebula-core"].unsafeRoutes
	    | map(select(.route == "fd42:dead:feed:70::/64" and .via6 == "fd42:dead:beef:ee::2" and .install == true))
	    | length
	  ) == 1 and
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
	    .nodes["b-router-core-nebula"].unsafeRoutes
	    | map(.route)
	    | index("10.10.0.16/32") == null and index("fd42:dead:beef:1000:0:0:0:10/128") == null
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
	  .spec.runtimeNodes["c-router-lighthouse"].isLighthouse == true and
	  .spec.runtimeNodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
	  (.spec.runtimeNodes["c-router-lighthouse"].unsafeRoutes | length) == 0 and
	  (.spec.runtimeNodes["b-router-core-nebula"].unsafeRoutes | length) > 0 and
	  (.spec.runtimeNodes["b-router-core-nebula"].advertisedUnsafeNetworks | index("10.60.10.0/24") != null) and
	  (.spec.runtimeNodes["b-router-core-nebula"].advertisedUnsafeNetworks | index("10.50.0.0/32") == null) and
	  (.spec.runtimeNodes["b-router-core-nebula"].advertisedUnsafeNetworks | index("fd42:dead:feed:10::/64") != null) and
	  (.spec.runtimeNodes["c-router-nebula-core"].advertisedUnsafeNetworks | index("10.70.10.0/24") == null) and
	  .spec.lighthouses["east-west"].internal == true and
	  (.spec.lighthouses["east-west"].unsafeNetworks | index("fd42:dead:beef:10::/64") != null)
	' "$tmp_dir/bootstrap.json" >/dev/null

echo "PASS test-nebula-plan"
