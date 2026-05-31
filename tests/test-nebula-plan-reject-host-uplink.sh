#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-004-SMS-001-003
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-004-SMS-001-CMC-001-003
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
inventory_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix"

if nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    lib = flake.inputs.nixpkgs.lib;
    api = flake.libBySystem.x86_64-linux.renderer;
    cpmLib = flake.inputs.network-control-plane-model.libBySystem.x86_64-linux;
    controlPlane = cpmLib.compileAndBuildFromPaths {
      inputPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
    inventory = cpmLib.readInput "'"$inventory_path"'";
    lighthouse = inventory.controlPlane.sites.esp0xdeadbeef.site-c.overlays.east-west.runtimeNodes.c-router-lighthouse;
    badInventory = lib.recursiveUpdate inventory {
      controlPlane.sites.esp0xdeadbeef.site-a.overlays.east-west.runtimeNodes.c-router-lighthouse =
        lighthouse // { container = lighthouse.container // { hostBridge = "br-uplink1"; }; };
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

echo "PASS test-nebula-plan-reject-host-uplink"
