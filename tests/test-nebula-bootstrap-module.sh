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
      externalLighthouseReturnIpv4Cidrs = [ "10.70.10.0/24" ];
      externalLighthousePublicIpv4SecretPath = "/run/secrets/external-public-ipv4";
      externalLighthousePublicIpv6SecretPath = "/run/secrets/external-public-ipv6";
      externalLighthouseSshHostSecretPath = "/run/secrets/external-ssh-host";
      externalPortForwardNodeNames = [ "c-router-nebula-core" ];
      externalRemoteLighthouseEndpoint4 = "10.90.10.100";
      externalRemoteLighthouseEndpoint6 = "";
      externalSuppressPublicLighthouseStaticMap = true;
    };
    externalModule = api.buildExternalLighthouseNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = plan;
    };
  in
	  {
	    profileType = module.systemd.services.nebula-profile-bootstrap.serviceConfig.Type;
	    profileAfter = module.systemd.services.nebula-profile-bootstrap.after;
	    profileWants = module.systemd.services.nebula-profile-bootstrap.wants;
	    profileScript = module.systemd.services.nebula-profile-bootstrap.script;
	    spec = builtins.fromJSON module.environment.etc."s-router-test/nebula-bootstrap-spec.json".text;
	    tmpfiles = module.systemd.tmpfiles.rules;
	    externalServices = builtins.attrNames externalModule.systemd.services;
	    externalEastWestUnit = externalModule.systemd.services.nebula-s-router-test-lighthouse-east-west or null;
	    externalFirewall = externalModule.networking.firewall;
  }
' > "$tmp_dir/bootstrap.json"

jq -e '
	  .profileType == "oneshot" and
	  (.profileAfter | index("container@c-router-lighthouse.service") == null) and
	  (.profileWants | index("container@c-router-lighthouse.service") == null) and
	  (.spec.runtimeNodes["b-router-core-nebula"].routePreparation.removeRoutes
	    | index("0.0.0.0/1") != null and index("::/1") != null) and
	  .spec.runtimeNodes["c-router-lighthouse"].isLighthouse == true and
	  .spec.runtimeNodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
	  (.spec.runtimeNodes["c-router-lighthouse"].unsafeRoutes | length) == 0 and
	  (.spec.runtimeNodes["c-router-lighthouse"].groupsCsv | split(",") | index("lighthouse") != null) and
	  .spec.lighthouses["east-west"].internal == true and
	  (.spec.lighthouses["east-west"].unsafeNetworks | index("::/1") != null) and
	  (.tmpfiles | index("d /persist/nebula-runtime 0700 root root -") != null)
	' "$tmp_dir/bootstrap.json" >/dev/null

	jq -e '
	  (.externalServices | index("nebula-s-router-test-lighthouse-east-west") == null) and
	  .externalEastWestUnit == null and
	  (.externalFirewall.allowedUDPPorts | index(4242) == null)
	' "$tmp_dir/bootstrap.json" >/dev/null

jq -r .profileScript "$tmp_dir/bootstrap.json" > "$tmp_dir/profile-script.sh"

grep -F "external_lighthouse_return_ipv4_cidrs_csv='10.70.10.0/24'" "$tmp_dir/profile-script.sh" >/dev/null
grep -F "external_lighthouse_public_ipv4_secret=/run/secrets/external-public-ipv4" "$tmp_dir/profile-script.sh" >/dev/null
grep -F "external_lighthouse_public_ipv6_secret=/run/secrets/external-public-ipv6" "$tmp_dir/profile-script.sh" >/dev/null
grep -F "external_lighthouse_ssh_host_secret=/run/secrets/external-ssh-host" "$tmp_dir/profile-script.sh" >/dev/null
grep -F "external_remote_lighthouse_endpoint4=10.90.10.100" "$tmp_dir/profile-script.sh" >/dev/null
grep -F "external_remote_lighthouse_endpoint6=''" "$tmp_dir/profile-script.sh" >/dev/null
grep -F "external_suppress_public_lighthouse_static_map=1" "$tmp_dir/profile-script.sh" >/dev/null
grep -F "external_port_forward_node_names_json='[\"c-router-nebula-core\"]'" "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'install_profile "$node_name" remote' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'if [ "$profile_context" = "remote" ]; then' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'if [ -n "$external_remote_lighthouse_endpoint4" ] || [ -n "$external_remote_lighthouse_endpoint6" ]; then' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'printf '\''    - "%s:%s"\n'\'' "$external_remote_lighthouse_endpoint4" "$lighthouse_port"' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '[ -z "$external_remote_lighthouse_endpoint4" ] \' "$tmp_dir/profile-script.sh" >/dev/null
grep -F "printf '  hosts: []\\n'" "$tmp_dir/profile-script.sh" >/dev/null
grep -F '"$external_node_name" != "$profile_name"' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'external_static_host_map_yaml' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '[.[$n].certCidr4, .[$n].certCidr6] | .[]? | sub("/.*$"; "")' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'nebula_control_networks_csv' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '.[$n].advertisedUnsafeNetworks | join(",")' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '.[$n].advertisedUnsafeNetworks' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'endswith("/32") or endswith("/128")' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'remote_runtime_nodes="$(' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '/persist/nebula-runtime/profiles/$node_name' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'systemctl restart container@\$target_container.service' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '+ (if (.route | contains(":")) then "1280" else "1200" end)' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '(.via6 // .via // "__LIGHTHOUSE_IPV6__")' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '(.via4 // .via // "__LIGHTHOUSE_IPV4__")' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'disabled: true' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'mtu: 1200' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'if [ -n "$lighthouse_endpoint6" ]; then' "$tmp_dir/profile-script.sh" >/dev/null
! grep -F '    - "[$lighthouse_endpoint6]:$lighthouse_port"' "$tmp_dir/profile-script.sh" >/dev/null
! grep -F 'extra_route_yaml="    - route: $delegated_prefix' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'local_cidr: $delegated_prefix' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'ip6tables -C FORWARD -i eth0 -o \$interface_name -d \"\$cidr\" -j ACCEPT' \
  "$tmp_dir/profile-script.sh" >/dev/null && {
    echo "renderer must not mutate remote external lighthouse ip6tables rules" >&2
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
