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
	  .overlays["esp0xdeadbeef::site-a::east-west"].lighthouse.port == "4242" and
	  .overlays["esp0xdeadbeef::site-c::east-west"].lighthouse.node == "c-router-lighthouse" and
	  .nodes["nebula-core"].materialization.container.profile == "core-client" and
	  .nodes["nebula-core"].materialization.container.hostBridge == "dmz" and
	  .nodes["c-router-lighthouse"].materialization.container.hostBridge == "dmz" and
	  .nodes["s-router-core-nebula"].relay.relays == ["100.96.10.3"] and
	  .nodes["b-router-core-nebula"].relay.relays == ["100.96.10.3"] and
	  .nodes["c-router-nebula-core"].relay.amRelay == true and
	  .nodes["c-router-nebula-core"].materialization.container.profile == "core-router-nebula"
	' "$tmp_dir/plan.json" >/dev/null

if nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
    cpmLib = flake.inputs.network-control-plane-model.libBySystem.x86_64-linux;
    controlPlane = cpmLib.compileAndBuildFromPaths {
      inputPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
    inventory = cpmLib.readInput "'"$inventory_path"'";
    badInventory = inventory // {
      controlPlane = inventory.controlPlane // {
        sites = inventory.controlPlane.sites // {
          esp0xdeadbeef = inventory.controlPlane.sites.esp0xdeadbeef // {
            site-a = inventory.controlPlane.sites.esp0xdeadbeef.site-a // {
              overlays = inventory.controlPlane.sites.esp0xdeadbeef.site-a.overlays // {
                east-west = inventory.controlPlane.sites.esp0xdeadbeef.site-a.overlays.east-west // {
                  runtimeNodes = inventory.controlPlane.sites.esp0xdeadbeef.site-a.overlays.east-west.runtimeNodes // {
                    nebula-core =
                      inventory.controlPlane.sites.esp0xdeadbeef.site-a.overlays.east-west.runtimeNodes.nebula-core
                      // {
                        container =
                          inventory.controlPlane.sites.esp0xdeadbeef.site-a.overlays.east-west.runtimeNodes.nebula-core.container
                          // { hostBridge = "br-uplink1"; };
                      };
                  };
                };
              };
            };
          };
        };
      };
    };
  in
    api.buildNebulaPlan {
      inherit controlPlane;
      inventory = badInventory;
    }
' >"$tmp_dir/invalid.json" 2>"$tmp_dir/invalid.err"; then
  echo "FAIL expected host uplink bridge rejection" >&2
  exit 1
fi

grep -F "must not attach a Nebula runtime node directly to deployment host uplink bridge 'br-uplink1'" \
  "$tmp_dir/invalid.err" >/dev/null

if nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
    cpmLib = flake.inputs.network-control-plane-model.libBySystem.x86_64-linux;
    controlPlane = cpmLib.compileAndBuildFromPaths {
      inputPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
    inventory = cpmLib.readInput "'"$inventory_path"'";
    badInventory = inventory // {
      controlPlane = inventory.controlPlane // {
        sites = inventory.controlPlane.sites // {
          espbranch = inventory.controlPlane.sites.espbranch // {
            site-b = inventory.controlPlane.sites.espbranch.site-b // {
              overlays = inventory.controlPlane.sites.espbranch.site-b.overlays // {
                east-west = inventory.controlPlane.sites.espbranch.site-b.overlays.east-west // {
                  runtimeNodes = inventory.controlPlane.sites.espbranch.site-b.overlays.east-west.runtimeNodes // {
                    b-router-core-nebula =
                      inventory.controlPlane.sites.espbranch.site-b.overlays.east-west.runtimeNodes.b-router-core-nebula
                      // {
                        relay = {
                          relays = [ "missing-relay-node" ];
                        };
                      };
                  };
                };
              };
            };
          };
        };
      };
    };
  in
    api.buildNebulaPlan {
      inherit controlPlane;
      inventory = badInventory;
    }
' >"$tmp_dir/invalid-relay.json" 2>"$tmp_dir/invalid-relay.err"; then
  echo "FAIL expected unknown relay node rejection" >&2
  exit 1
fi

grep -F "relay.relays references unknown runtime node 'missing-relay-node'" \
  "$tmp_dir/invalid-relay.err" >/dev/null

echo "PASS test-nebula-plan-from-paths"
