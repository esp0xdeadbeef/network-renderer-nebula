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
      externalPortForwardPublicIpv4SecretPath = "/run/secrets/portforward-public-ipv4";
      externalPortForwardPublicIpv6SecretPath = "/run/secrets/portforward-public-ipv6";
      externalPortForwardNodeNames = [ "c-router-nebula-core" ];
      externalRuntimeNodeNames = [ "c-router-nebula-core" ];
      runtimeListenHosts.c-router-nebula-core = "172.31.254.4";
      externalRemoteLighthouseEndpoint4 = "10.90.10.100";
      externalSuppressPublicLighthouseStaticMap = true;
    };
  in
    module.systemd.services.nebula-profile-bootstrap.script
' | jq -r . > "$tmp_dir/profile-script.sh"

grep -F 'external_port_forward_node_names_json='\''["c-router-nebula-core"]'\''' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'external_static_host_map_yaml' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'external_node_endpoint4="$port_forward_endpoint"' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'external_node_endpoint6="$port_forward_endpoint6"' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'lighthouse_owned_endpoint="$lighthouse_endpoint"' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'lighthouse_owned_endpoint6="$lighthouse_endpoint6"' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '[ "$external_node_endpoint4" = "$lighthouse_owned_endpoint" ] && [ "$external_node_port" = "$lighthouse_port" ]' "$tmp_dir/profile-script.sh" >/dev/null
grep -F '[ "$external_node_endpoint6" = "$lighthouse_owned_endpoint6" ] && [ "$external_node_port" = "$lighthouse_port" ]' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'printf '\''    - "%s:%s"\n'\'' "$external_node_endpoint4" "$external_node_port"' "$tmp_dir/profile-script.sh" >/dev/null
grep -F 'printf '\''    - "[%s]:%s"\n'\'' "$external_node_endpoint6" "$external_node_port"' "$tmp_dir/profile-script.sh" >/dev/null

if grep -F '.[$n].lighthouse.node == $n' "$tmp_dir/profile-script.sh" >/dev/null; then
  echo "network-renderer-nebula: public-forwarded relays must receive static_host_map entries even when they are not their own lighthouse" >&2
  exit 1
fi

echo "PASS test-nebula-public-forwarded-relay-static-map"
