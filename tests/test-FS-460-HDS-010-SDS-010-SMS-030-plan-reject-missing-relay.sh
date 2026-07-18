#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-030
# UPDATED: merged inventory into controlPlane — renderer consumes CPM output only.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"

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
    # Inject a bad relay reference into the CPM data tree
    badControlPlane = lib.recursiveUpdate controlPlane {
      control_plane_model.data.espbranch.site-b.overlays.east-west.runtimeNodes.b-router-core-nebula = {
        relay.relays = [ "missing-relay-node" ];
      };
    };
  in
    api.buildNebulaPlan {
      controlPlane = badControlPlane;
    }
' >"$tmp_dir/invalid-relay.json" 2>"$tmp_dir/invalid-relay.err"; then
  echo "FAIL expected unknown relay node rejection" >&2
  exit 1
fi

grep -F "relay.relays references unknown runtime node 'missing-relay-node'" \
  "$tmp_dir/invalid-relay.err" >/dev/null

echo "PASS test-nebula-plan-reject-missing-relay"
