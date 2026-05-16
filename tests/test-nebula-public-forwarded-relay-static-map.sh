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
    nodeName = "c-router-nebula-core";
    module = api.buildNebulaRuntimeNixosModule {
      inherit pkgs nodeName;
      runtimeNode = plan.nodes.${nodeName} // {
        service = (plan.nodes.${nodeName}.service or { }) // {
          listenHost = "172.31.254.4";
        };
      };
    };
  in
    module.services.nebula.networks.runtime
' > "$tmp_dir/network.json"

jq -e '
  .listen.host == "172.31.254.4" and
  .staticHostMap != {} and
  .isRelay == true and
  .settings.relay.am_relay == true
' "$tmp_dir/network.json" >/dev/null

source_file="${repo_root}/s88/Enterprise/runtime/nixos-module.nix"
! grep -F '.[$n].lighthouse.node == $n' "$source_file" >/dev/null
! grep -F 'profile-bootstrap.bash' "$source_file" >/dev/null

echo "PASS test-nebula-public-forwarded-relay-static-map"
