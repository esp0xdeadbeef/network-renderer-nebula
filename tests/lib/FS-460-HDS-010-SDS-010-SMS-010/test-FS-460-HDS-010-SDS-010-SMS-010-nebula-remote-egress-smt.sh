#!/usr/bin/env bash
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake ("path:'"${repo_root}"'");
    api = flake.libBySystem.x86_64-linux.renderer;

    render = routes: api.buildNebulaPlan {
      controlPlane = mkControlPlane routes;
    };

    overlayRoute = {
      proto = "overlay";
      overlay = "east-west";
      peerSite = "enterprise.remote";
      family = 4;
      dst = "10.80.0.0/24";
      intent.kind = "overlay-reachability";
    };

    delegatedDefault = {
      proto = "overlay";
      overlay = "east-west";
      peerSite = "enterprise.remote";
      family = 4;
      dst = "0.0.0.0/0";
      policyOnly = true;
      intent.kind = "delegated-public-egress";
    };

    underlayReadiness = {
      proto = "overlay";
      overlay = "east-west";
      peerSite = "enterprise.remote";
      family = "ipv4";
      sourceFile = "/run/secrets/remote-lighthouse-ipv4";
      intent = {
        kind = "overlay-underlay-reachability";
        source = "overlay-underlay-endpoint";
      };
    };

    mkControlPlane = routes: {
      control_plane_model.data.enterprise = {
        local = {
          enterprise = "enterprise";
          siteName = "local";
          domains.tenants = [
            {
              name = "client";
              ipv4 = "10.10.0.0/24";
              routedPrefixes = [
                {
                  family = "ipv4";
                  allocation = "runtime";
                  sourceFile = "/run/secrets/client-prefix-v4";
                }
              ];
            }
          ];
          runtimeTargets."core-target".effectiveRuntimeRealization.interfaces."overlay-east-west" = {
            logicalNode = "core";
            backingRef.name = "east-west";
            sourceKind = "overlay";
            routes.ipv4 = routes;
          };
          overlays.east-west = {
            provider = "nebula";
            peerSites = [ "enterprise.remote" ];
            runtimeNodes.core = {
              groups = [ "core" ];
              container.targetContainer = "core";
              service = {
                interface = "nebula1";
                name = "nebula-runtime";
                listenHost = "127.0.0.1";
              };
            };
            nodes.core = {
              addr4 = "100.96.0.1/24";
              addr6 = "fd42:dead:beef::1/64";
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
        remote = {
          enterprise = "enterprise";
          siteName = "remote";
          overlays.east-west = {
            provider = "nebula";
            terminateOn = [ "remote-core" ];
            nodes.remote-core = {
              addr4 = "100.96.0.2/24";
              addr6 = "fd42:dead:beef::2/64";
            };
            runtimeNodes.remote-core = {
              groups = [ "core" ];
              container.targetContainer = "remote-core";
              service = {
                interface = "nebula1";
                name = "nebula-runtime";
                listenHost = "127.0.0.1";
              };
            };
          };
        };
      };
    };

    goodPlan = render [ overlayRoute delegatedDefault underlayReadiness ];
    missingPeer = builtins.tryEval (render [ (builtins.removeAttrs overlayRoute [ "peerSite" ]) ]).nodes.core.unsafeRoutes;
    badDefault = builtins.tryEval (render [ (delegatedDefault // { intent.kind = "overlay-reachability"; }) ]).nodes.core.unsafeRoutes;
  in
  {
    unsafeRoutes = goodPlan.nodes.core.unsafeRoutes;
    dynamicFirewallCidrs = goodPlan.nodes.core.dynamicFirewallCidrs;
    dynamicUnsafeRoutes = goodPlan.nodes.core.dynamicUnsafeRoutes;
    missingPeerRejected = !missingPeer.success;
    badDefaultRejected = !badDefault.success;
  }
' > "${tmp_dir}/observed.json"

jq -e '
  . as $observed
  | $observed.unsafeRoutes as $routes
  | {
      ok:
        (
          ($routes | map(select(.route == "10.80.0.0/24" and .via4 == "100.96.0.2" and .install == true)) | length) == 1
          and ($routes | map(select(.route == "0.0.0.0/1" and .via4 == "100.96.0.2" and .install == false)) | length) == 1
          and ($routes | map(select(.route == "128.0.0.0/1" and .via4 == "100.96.0.2" and .install == false)) | length) == 1
          and ($routes | map(.route) | index("0.0.0.0/0") == null)
          and ($routes | map(.route) | index("/run/secrets/remote-lighthouse-ipv4") == null)
          and ($observed.dynamicFirewallCidrs | map(select(.sourceFile == "/run/secrets/remote-lighthouse-ipv4" and .family == "ipv4")) | length) == 1
          and ($observed.dynamicUnsafeRoutes | length) == 0
          and $observed.missingPeerRejected == true
          and $observed.badDefaultRejected == true
        ),
      observed: $observed
    }
' "${tmp_dir}/observed.json" > "${tmp_dir}/checked.json"

if ! jq -e '.ok == true' "${tmp_dir}/checked.json" >/dev/null; then
  echo "FAIL fs460-nebula-remote-egress-smt: Nebula renderer did not satisfy FS-460 split SMS construction checks" >&2
  jq . "${tmp_dir}/checked.json" >&2
  exit 1
fi

echo "PASS fs460-nebula-remote-egress-smt"
