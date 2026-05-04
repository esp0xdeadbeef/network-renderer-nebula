#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    system = "x86_64-linux";
    api = flake.libBySystem.${system}.renderer;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    module = api.buildNebulaRuntimeNixosModule {
      inherit pkgs;
      nodeName = "b-router-core-nebula";
    };
    service = module.systemd.services.nebula-runtime;
  in
  {
    tmpfiles = module.systemd.tmpfiles.rules;
    firewall = module.networking.firewall;
    inherit service;
  }
' > "$tmp_dir/runtime-module.json"

jq -e '
  (.tmpfiles | index("d /persist/etc/nebula 0700 root root -") != null) and
  (.firewall.extraInputRules | contains("s88-nebula-runtime-input")) and
  (.firewall.extraForwardRules | contains("s88-nebula-runtime-forward-in")) and
  (.firewall.extraForwardRules | contains("s88-nebula-runtime-forward-out")) and
  (.service.serviceConfig.ExecStart | contains("nebula -config /persist/etc/nebula/config.yml"))
' "$tmp_dir/runtime-module.json" >/dev/null

jq -r '.service.serviceConfig.ExecStartPre[]' "$tmp_dir/runtime-module.json" > "$tmp_dir/exec-start-pre.txt"
grep -F 'config.yml' "$tmp_dir/exec-start-pre.txt" >/dev/null
grep -F 'nebula-runtime-prepare-underlay-routes-b-router-core-nebula' "$tmp_dir/exec-start-pre.txt" >/dev/null

prepare_script="$(grep -F 'nebula-runtime-prepare-underlay-routes-b-router-core-nebula' "$tmp_dir/exec-start-pre.txt" | tail -n1)"
test -n "$prepare_script"

source_file="${repo_root}/s88/Enterprise/runtime/nixos-module.nix"
grep -F 'route-preparation.json' "$source_file" >/dev/null
grep -F 'missing rendered route preparation plan' "$source_file" >/dev/null
grep -F 'ip route replace "$endpoint/32"' "$source_file" >/dev/null
grep -F 'ip -6 route replace "$endpoint/128"' "$source_file" >/dev/null
! grep -F 'grep -E' "$source_file" >/dev/null

echo "PASS test-nebula-runtime-module"
