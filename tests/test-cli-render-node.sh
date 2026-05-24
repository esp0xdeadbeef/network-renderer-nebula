#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'chmod -R u+w "$tmp_dir" 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
inventory_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    system = "x86_64-linux";
    cpmLib = flake.inputs.network-control-plane-model.libBySystem.${system};
  in
  {
    controlPlane = cpmLib.compileAndBuildFromPaths {
      inputPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
    inventory = cpmLib.readInput "'"$inventory_path"'";
  }
' >"$tmp_dir/cpm-bundle.json"

nix build --no-warn-dirty --print-out-paths "${repo_root}#default" >"$tmp_dir/package-path"
runner="$(cat "$tmp_dir/package-path")/bin/network-renderer-nebula"

"$runner" render-node \
  --cpm "$tmp_dir/cpm-bundle.json" \
  --node b-router-core-nebula \
  --out "$tmp_dir/modeled"

jq -e '
  .nodeName == "b-router-core-nebula" and
  .selectedOverlayId == "espbranch::site-b::east-west" and
  .runtimeNode.overlayAddresses[0] == "100.96.10.2/24" and
  (.runtimeNode.unsafeRoutes | length) > 0 and
  (.runtimeNode.materialization.unmanaged // false | not)
' "$tmp_dir/modeled/runtime-node.json" >/dev/null

NIX_REMOTE="local?root=$tmp_dir/local-nix-store" "$runner" render-node \
  --cpm "$tmp_dir/cpm-bundle.json" \
  --node b-router-core-nebula \
  --out "$tmp_dir/modeled-local-store"

jq -e '
  .nodeName == "b-router-core-nebula" and
  .selectedOverlayId == "espbranch::site-b::east-west" and
  .runtimeNode.overlayAddresses[0] == "100.96.10.2/24" and
  (.runtimeNode.unsafeRoutes | length) > 0
' "$tmp_dir/modeled-local-store/runtime-node.json" >/dev/null

"$runner" render-node \
  --cpm "$tmp_dir/cpm-bundle.json" \
  --node laptop-adhoc-01 \
  --extra-node \
  --overlay espbranch::site-b::east-west \
  --addr4 100.96.10.77/24 \
  --addr6 fd42:dead:beef:ee::77/64 \
  --group laptop \
  >"$tmp_dir/laptop.json"

jq -e '
  .nodeName == "laptop-adhoc-01" and
  .selectedOverlayId == "espbranch::site-b::east-west" and
  .runtimeNode.materialization.unmanaged == true and
  (.runtimeNode.groups | index("unmanaged") != null and index("laptop") != null) and
  .runtimeNode.overlayAddresses == ["100.96.10.77/24", "fd42:dead:beef:ee::77/64"] and
  (.runtimeNode.unsafeRoutes | length) == 0 and
  (.runtimeNode.dynamicUnsafeRoutes | length) == 0
' "$tmp_dir/laptop.json" >/dev/null

if "$runner" render-node --cpm "$tmp_dir/cpm-bundle.json" --node laptop-adhoc-02 2>"$tmp_dir/error.log"; then
  echo "expected unknown unmanaged node without --extra-node to fail" >&2
  exit 1
fi
grep -F "pass --extra-node" "$tmp_dir/error.log" >/dev/null

echo "PASS test-cli-render-node"
