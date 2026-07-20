#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-041
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

if rg -nF 'or "lighthouse"' "${repo_root}/s88/Enterprise/bootstrap/external-lighthouse-module" >/dev/null 2>&1; then
  echo "FAIL nebula-fail-closed-contract: external lighthouse node fallback still present" >&2
  rg -nF 'or "lighthouse"' "${repo_root}/s88/Enterprise/bootstrap/external-lighthouse-module" >&2
  exit 1
fi

if rg -nF 'host = "[::]"' "${repo_root}/s88/Enterprise/bootstrap/external-lighthouse-module.nix" >/dev/null 2>&1; then
  echo "FAIL nebula-fail-closed-contract: external lighthouse listen host is still hardcoded" >&2
  rg -nF 'host = "[::]"' "${repo_root}/s88/Enterprise/bootstrap/external-lighthouse-module.nix" >&2
  exit 1
fi

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"${repo_root}"');
    system = "x86_64-linux";
    api = flake.libBySystem.${system}.renderer;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    mkPlan = lighthouse: {
      overlays.east-west = {
        name = "east-west";
        inherit lighthouse;
      };
      nodes = { };
    };
    good = api.buildExternalLighthouseNixosModule {
      inherit pkgs;
      consumerName = "s-router-test";
      nebulaRuntimePlan = mkPlan {
        node = "external-lighthouse";
        listenHost = "198.51.100.10";
        port = "4242";
        endpoint = "198.51.100.10";
        endpoint6 = "2001:db8:51::10";
        overlayAddresses = [ "100.96.10.254/24" "fd42:dead:beef:ee::254/64" ];
        overlayIps = [ "100.96.10.254" "fd42:dead:beef:ee::254" ];
      };
    };
    missingNode = builtins.tryEval (builtins.deepSeq (api.buildExternalLighthouseNixosModule {
      inherit pkgs;
      consumerName = "s-router-test";
      nebulaRuntimePlan = mkPlan {
        listenHost = "198.51.100.10";
        port = "4242";
        endpoint = "198.51.100.10";
        overlayAddresses = [ "100.96.10.254/24" "fd42:dead:beef:ee::254/64" ];
      };
    }).environment.etc."s-router-test/external_lighthouse-nebula-lighthouses.json".text true);
    missingListenHost = builtins.tryEval (builtins.deepSeq (api.buildExternalLighthouseNixosModule {
      inherit pkgs;
      consumerName = "s-router-test";
      nebulaRuntimePlan = mkPlan {
        node = "external-lighthouse";
        port = "4242";
        endpoint = "198.51.100.10";
        overlayAddresses = [ "100.96.10.254/24" "fd42:dead:beef:ee::254/64" ];
      };
    }).services.nebula.networks."lighthouse-east-west".listen.host true);
  in
  {
    externalSpec = builtins.fromJSON good.environment.etc."s-router-test/external_lighthouse-nebula-lighthouses.json".text;
    listen = good.services.nebula.networks."lighthouse-east-west".listen;
    missingNodeRejected = !missingNode.success;
    missingListenHostRejected = !missingListenHost.success;
  }
' >"${tmp_dir}/observed.json"

jq -e '
  .externalSpec[0].certBaseName == "east-west-external-lighthouse" and
  .externalSpec[0].listenHost == "198.51.100.10" and
  .listen.host == "198.51.100.10" and
  .listen.port == 4242 and
  .missingNodeRejected == true and
  .missingListenHostRejected == true
' "${tmp_dir}/observed.json" >/dev/null || {
  echo "FAIL nebula-fail-closed-contract: expected external lighthouse fail-closed behavior was not observed" >&2
  jq . "${tmp_dir}/observed.json" >&2
  exit 1
}

echo "PASS nebula-fail-closed-contract"
