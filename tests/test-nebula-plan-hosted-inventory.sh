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
    lib = flake.inputs.nixpkgs.lib;
    api = flake.libBySystem.x86_64-linux.renderer;
    cpmLib = flake.inputs.network-control-plane-model.libBySystem.x86_64-linux;
    controlPlane = cpmLib.compileAndBuildFromPaths {
      inputPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
    inventory = cpmLib.readInput "'"$inventory_path"'";
    site = inventory.controlPlane.sites.esp0xdeadbeef.site-c;
    overlay = site.overlays.east-west;
    lighthouse = overlay.runtimeNodes.c-router-lighthouse;
    hostedInventory = lib.recursiveUpdate inventory {
      controlPlane.sites.esp0xdeadbeef.site-c.overlays.east-west.runtimeNodes.c-router-lighthouse =
        lighthouse // { container = lighthouse.container // { host = "site-c-host"; }; };
    };
  in
    api.buildNebulaPlan {
      inherit controlPlane;
      inventory = hostedInventory;
    }
' > "$tmp_dir/hosted-plan.json"

jq -e '.nodes["c-router-lighthouse"].materialization.deploymentHost == "site-c-host"' \
  "$tmp_dir/hosted-plan.json" >/dev/null

echo "PASS test-nebula-plan-hosted-inventory"
