#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if rg -n 'runtimeNode\.unsafeRoutes|hasInfix|contains\("nebula"\)|contains\("core"\)' \
  "${repo_root}" \
  --glob '*.nix' \
  --glob '!flake.lock' \
  --glob '!tests/test-cpm-overlay-contract-boundary.sh' >/tmp/network-renderer-nebula-boundary-hits.$$; then
  cat >&2 <<EOF
FATAL network-renderer-nebula CPM overlay contract boundary violation.

Nebula route/firewall behavior must come from explicit CPM/provider contracts.
Do not derive policy from runtime inventory unsafeRoutes or node-name strings.

Current boundary hits:
EOF
  cat /tmp/network-renderer-nebula-boundary-hits.$$ >&2
  rm -f /tmp/network-renderer-nebula-boundary-hits.$$
  exit 1
fi

rm -f /tmp/network-renderer-nebula-boundary-hits.$$
nix eval --impure --no-warn-dirty --expr '
  let
    flake = builtins.getFlake (toString '"$repo_root"');
    api = flake.libBySystem.x86_64-linux.renderer;
    badControlPlane = {
      control_plane_model.data.enterprise.site = {
        runtimeTargets = { };
        overlays.east-west = {
          nodes.core = {
            addr4 = "100.96.0.10";
            addr6 = "fd42:dead:beef::10";
          };
          nebula.lighthouse = {
            node = "core";
            endpoint = "198.51.100.10";
            endpoint6 = "2001:db8::10";
            port = 4242;
          };
          ipam = {
            ipv4.prefix = "100.96.0.0/24";
            ipv6.prefix = "fd42:dead:beef::/64";
          };
        };
      };
    };
    badInventory = {
      controlPlane.sites.enterprise.site.overlays.east-west = {
        provider = "nebula";
        runtimeNodes.core.unsafeRoutes = [
          {
            route = "0.0.0.0/1";
            via4 = "100.96.0.1";
            install = true;
          }
        ];
      };
    };
    plan = api.buildNebulaPlan {
      controlPlane = badControlPlane;
      inventory = badInventory;
    };
    result = builtins.tryEval plan.nodes.core.unsafeRoutes;
  in
    if result.success then
      throw "network-renderer-nebula: inventory runtimeNodes.*.unsafeRoutes unexpectedly evaluated"
    else
      true
' >/dev/null
echo "PASS cpm-overlay-contract-boundary"
