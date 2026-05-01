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
      hetznerIpv4NatCidrs = [ "10.70.10.0/24" ];
    };
  in
  {
    profileType = module.systemd.services.nebula-profile-bootstrap.serviceConfig.Type;
    profileScript = module.systemd.services.nebula-profile-bootstrap.script;
    spec = builtins.fromJSON module.environment.etc."s-router-test/nebula-bootstrap-spec.json".text;
    tmpfiles = module.systemd.tmpfiles.rules;
  }
' > "$tmp_dir/bootstrap.json"

jq -e '
  .profileType == "oneshot" and
  (.spec.runtimeNodes["b-router-core-nebula"].routePreparation.removeRoutes
    | index("0.0.0.0/1") != null and index("::/1") != null) and
  (.spec.lighthouses["east-west"].unsafeNetworks | index("::/1") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime 0700 root root -") != null)
' "$tmp_dir/bootstrap.json" >/dev/null

jq -r .profileScript "$tmp_dir/bootstrap.json" > "$tmp_dir/profile-script.sh"

grep -F "hetzner_ipv4_nat_cidrs_csv='10.70.10.0/24'" "$tmp_dir/profile-script.sh" >/dev/null
grep -F '+ (if (.route | contains(":")) then "1280" else "1200" end)' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'mtu: 1200' "$tmp_dir/profile-script.sh" >/dev/null
! grep -F 'extra_route_yaml="    - route: $delegated_prefix' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'local_cidr: $delegated_prefix' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'ip6tables -C FORWARD -i eth0 -o \$interface_name -d \"\$cidr\" -j ACCEPT' \
  "$tmp_dir/profile-script.sh" >/dev/null

grep -F 'UNSAFEFWOUT' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'UNSAFEFWIN' "$tmp_dir/profile-script.sh" >/dev/null

first_lighthouse_cert_block="$tmp_dir/first-lighthouse-cert-block.sh"
awk '
  /printf '\''%s'\'' "\$lighthouses_json" \| jq -r '\''keys\[\]'\'' \| while read -r lighthouse_id; do/ {
    if (++seen == 1) in_block = 1
  }
  in_block { print }
  in_block && /issue_node_cert "\$cert_base_name" "\$cert_networks" "lab,lighthouse" "\$unsafe_networks"/ {
    exit
  }
' "$tmp_dir/profile-script.sh" > "$first_lighthouse_cert_block"
! grep -F 'access_prefixes_all' "$first_lighthouse_cert_block" >/dev/null

echo "PASS test-nebula-bootstrap-module"
