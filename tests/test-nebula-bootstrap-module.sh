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
    hetznerModule = api.buildHetznerLighthouseNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = plan;
      hetznerIpv4NatCidrs = [ "10.70.10.0/24" ];
      externalInterface = "ens3";
    };
  in
  {
    profileType = module.systemd.services.nebula-profile-bootstrap.serviceConfig.Type;
    profileScript = module.systemd.services.nebula-profile-bootstrap.script;
    spec = builtins.fromJSON module.environment.etc."s-router-test/nebula-bootstrap-spec.json".text;
    tmpfiles = module.systemd.tmpfiles.rules;
    hetznerServices = builtins.attrNames hetznerModule.systemd.services;
    hetznerEastWestUnit = hetznerModule.systemd.services.nebula-s-router-test-lighthouse-east-west;
    hetznerNat = hetznerModule.networking.nat;
    hetznerFirewall = hetznerModule.networking.firewall;
  }
' > "$tmp_dir/bootstrap.json"

jq -e '
  .profileType == "oneshot" and
  (.spec.runtimeNodes["b-router-core-nebula"].routePreparation.removeRoutes
    | index("0.0.0.0/1") != null and index("::/1") != null) and
  (.spec.lighthouses["east-west"].unsafeNetworks | index("::/1") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime 0700 root root -") != null)
' "$tmp_dir/bootstrap.json" >/dev/null

jq -e '
  (.hetznerServices | index("nebula-s-router-test-lighthouse-east-west") != null) and
  .hetznerEastWestUnit.unitConfig.ConditionPathExists == "/persist/nebula-runtime/lighthouses/east-west-hetzner-nebula-prodtest-01/east-west-hetzner-nebula-prodtest-01.config.yml" and
  (.hetznerEastWestUnit.serviceConfig.ExecStart | contains("/persist/nebula-runtime/lighthouses/east-west-hetzner-nebula-prodtest-01/east-west-hetzner-nebula-prodtest-01.config.yml")) and
  .hetznerNat.content.externalInterface == "ens3" and
  (.hetznerNat.content.internalIPs | index("10.70.10.0/24") != null) and
  (.hetznerFirewall.allowedUDPPorts | index(4242) != null)
' "$tmp_dir/bootstrap.json" >/dev/null

jq -r .profileScript "$tmp_dir/bootstrap.json" > "$tmp_dir/profile-script.sh"

grep -F "hetzner_ipv4_nat_cidrs_csv='10.70.10.0/24'" "$tmp_dir/profile-script.sh" >/dev/null
grep -F '+ (if (.route | contains(":")) then "1280" else "1200" end)' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '(.via6 // .via // "__LIGHTHOUSE_IPV6__")' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '(.via4 // .via // "__LIGHTHOUSE_IPV4__")' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'mtu: 1200' "$tmp_dir/profile-script.sh" >/dev/null
! grep -F 'extra_route_yaml="    - route: $delegated_prefix' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'local_cidr: $delegated_prefix' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'ip6tables -C FORWARD -i eth0 -o \$interface_name -d \"\$cidr\" -j ACCEPT' \
  "$tmp_dir/profile-script.sh" >/dev/null && {
    echo "renderer must not mutate remote Hetzner ip6tables rules" >&2
    exit 1
  }
! grep -F 'cat > /etc/systemd/system/$service_name.service' "$tmp_dir/profile-script.sh" >/dev/null
! grep -F 'curl -fsSL https://github.com/slackhq/nebula' "$tmp_dir/profile-script.sh" >/dev/null
! grep -F 'iptables -C' "$tmp_dir/profile-script.sh" >/dev/null
! grep -F 'ip6tables -C' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '/persist/nebula-runtime/lighthouses' "$tmp_dir/profile-script.sh" >/dev/null

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
