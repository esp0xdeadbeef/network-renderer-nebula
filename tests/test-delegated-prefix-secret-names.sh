#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --json \
  --expr '
    let
      flake = builtins.getFlake (toString '"${repo_root}"');
      renderer = flake.libBySystem.${builtins.currentSystem}.renderer;
      controlPlanes = [
        {
          control_plane_model.data.esp.hetz.runtimeTargets = {
            "old-validation-only" = {
              externalValidation.delegatedPrefixSecretName =
                "access-node-ipv6-prefix-old-validation-only";
            };
            "advertised-runtime-prefix" = {
              externalValidation.delegatedPrefixSecretName =
                "access-node-ipv6-prefix-stale-shortcut";
              advertisements.ipv6Ra = [
                {
                  delegatedPrefix.sourceFile =
                    "/run/secrets/access-node-ipv6-prefix-modeled-runtime";
                }
              ];
            };
          };
        }
      ];
    in
    renderer.delegatedPrefixSecretNames { inherit controlPlanes; }
  ' \
  | jq -e '
      . == ["access-node-ipv6-prefix-modeled-runtime"]
    ' >/dev/null || {
      echo "FAIL delegated-prefix-secret-names: externalValidation shortcuts must not be treated as routed-prefix secret inputs" >&2
      exit 1
    }

echo "PASS delegated-prefix-secret-names"
