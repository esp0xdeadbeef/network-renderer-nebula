#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-010
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/examples/s-router-public-overlay-service/intent.nix"
inventory_path="${labs_path}/examples/s-router-public-overlay-service/inventory-nixos.nix"

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
    plan = import "'"$repo_root"'/tests/nix/nebula-plan-from-inputs.nix" {
      repoRoot = "'"$repo_root"'";
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
    };
  in
    api.buildNebulaBootstrapSpec {
      nebulaRuntimePlan = plan;
      externalPortForwardNodeNames = [ "c-router-nebula-core" ];
      externalRuntimeNodeNames = [ "c-router-nebula-core" ];
      runtimeListenHosts.c-router-nebula-core = "172.31.254.4";
      sopsProfileSecretPrefix = "nebula-profile";
    }
' > "$tmp_dir/spec.json"

jq -e '
  .runtimeNodes["c-router-lighthouse"].isLighthouse == true and
  .runtimeNodes["c-router-nebula-core"].service.listenHost == "172.31.254.4" and
  .runtimeNodes["b-router-core-nebula"].relay.relays == [] and
  (.runtimeNodes["b-router-core-nebula"].unsafeRoutes | length) > 0 and
  (.runtimeNodes["c-router-nebula-core"].advertisedUnsafeNetworkSourceFiles | index("/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile") != null) and
  .lighthouses["east-west"].internal == true
' "$tmp_dir/spec.json" >/dev/null

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
  in
    api.buildNebulaBootstrapSpec {
      sopsProfileSecretPrefix = "nebula-profile";
      nebulaRuntimePlan = {
        overlays.test = {
          name = "test";
          lighthouse = {
            node = "exit";
            port = "4242";
            overlayAddresses = [ "100.96.0.1/24" "fd42:test::1/64" ];
            overlayIps = [ "100.96.0.1" "fd42:test::1" ];
          };
        };
        nodes.exit = {
          overlayId = "test";
          overlayAddresses = [ "100.96.0.1/24" "fd42:test::1/64" ];
          lighthouse = {
            node = "exit";
            port = "4242";
            overlayAddresses = [ "100.96.0.1/24" "fd42:test::1/64" ];
            overlayIps = [ "100.96.0.1" "fd42:test::1" ];
          };
          groups = [ "core" ];
          service = {
            interface = "nebula1";
            name = "nebula-runtime";
          };
          dynamicFirewallCidrs = [
            {
              family = "ipv6";
              sourceFile = "/run/secrets/access-node-ipv6-prefix-test";
            }
          ];
        };
      };
    }
' > "$tmp_dir/dynamic-source-spec.json"

jq -e '
  .runtimeNodes.exit.advertisedUnsafeNetworkSourceFiles
  == ["/run/secrets/access-node-ipv6-prefix-test"]
' "$tmp_dir/dynamic-source-spec.json" >/dev/null

echo "PASS test-nebula-bootstrap-spec"
