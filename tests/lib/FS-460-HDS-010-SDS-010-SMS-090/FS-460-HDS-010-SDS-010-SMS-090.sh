#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-090
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake ("path:'"${repo_root}"'");
    api = flake.libBySystem.x86_64-linux.renderer;
    ipam = {
      ipv4.prefix = "100.96.0.0/24";
      ipv6.prefix = "fd42:dead:beef::/64";
    };
    delegatedDefault4 = {
      proto = "overlay";
      overlay = "east-west";
      peerSite = "enterprise.remote";
      family = 4;
      dst = "0.0.0.0/0";
      policyOnly = true;
      intent.kind = "delegated-public-egress";
    };
    delegatedDefault6 = {
      proto = "overlay";
      overlay = "east-west";
      peerSite = "enterprise.remote";
      family = 6;
      dst = "::/0";
      policyOnly = true;
      intent.kind = "delegated-public-egress";
    };
    cp = {
      control_plane_model.data.enterprise = {
        local = {
          enterprise = "enterprise";
          siteName = "local";
          runtimeTargets.target.effectiveRuntimeRealization.interfaces.overlay = {
            logicalNode = "core";
            backingRef.name = "east-west";
            sourceKind = "overlay";
            routes.ipv4 = [ delegatedDefault4 ];
            routes.ipv6 = [ delegatedDefault6 ];
          };
          overlays.east-west = {
            provider = "nebula";
            peerSites = [ "enterprise.remote" ];
            inherit ipam;
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
          };
        };
        remote = {
          enterprise = "enterprise";
          siteName = "remote";
          overlays.east-west = {
            provider = "nebula";
            inherit ipam;
            nebula.lighthouse = {
              node = "remote-core";
              endpoint = "198.51.100.20";
              endpoint6 = "2001:db8::20";
              port = 4242;
            };
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
    plan = api.buildNebulaPlan { controlPlane = cp; };
  in
  {
    local = plan.nodes.core;
    remote = plan.nodes.remote-core;
  }
' > "${tmp_dir}/plan.json"

jq -e '
  .local as $local
  | .remote as $remote
  | ($local.nebulaNetwork.settings.nebulaFirewallRules.inbound | map(.local_cidr)) as $in
  | ($local.nebulaNetwork.settings.nebulaFirewallRules.outbound | map(.local_cidr)) as $out
  | ($local.unsafeRoutes | map(.route)) as $local_routes
  | ($remote.advertisedUnsafeNetworks // []) as $remote_advertised
  | {
      ok:
        (
          ($local_routes | index("0.0.0.0/1") != null)
          and ($local_routes | index("128.0.0.0/1") != null)
          and ($local_routes | index("::/1") != null)
          and ($local_routes | index("8000::/1") != null)
          and ($local_routes | index("0.0.0.0/0") == null)
          and ($local_routes | index("::/0") == null)
          and ($in | index("0.0.0.0/1") != null)
          and ($in | index("128.0.0.0/1") != null)
          and ($in | index("::/1") != null)
          and ($in | index("8000::/1") != null)
          and ($out | index("0.0.0.0/1") != null)
          and ($out | index("128.0.0.0/1") != null)
          and ($out | index("::/1") != null)
          and ($out | index("8000::/1") != null)
          and ($remote_advertised | index("0.0.0.0/1") != null)
          and ($remote_advertised | index("128.0.0.0/1") != null)
          and ($remote_advertised | index("::/1") != null)
          and ($remote_advertised | index("8000::/1") != null)
        ),
      localUnsafeRoutes: $local.unsafeRoutes,
      localFirewallDefaults: {
        inbound: ($in | map(select(. == "0.0.0.0/1" or . == "128.0.0.0/1" or . == "::/1" or . == "8000::/1"))),
        outbound: ($out | map(select(. == "0.0.0.0/1" or . == "128.0.0.0/1" or . == "::/1" or . == "8000::/1")))
      },
      remoteAdvertised: $remote_advertised
    }
' "${tmp_dir}/plan.json" > "${tmp_dir}/observed.json"

if ! jq -e '.ok == true' "${tmp_dir}/observed.json" >/dev/null; then
  echo "FAIL nebula-advertised-default-firewall: delegated defaults must be split, firewall-scoped, and advertised only as split networks" >&2
  jq . "${tmp_dir}/observed.json" >&2
  exit 1
fi

echo "PASS nebula-advertised-default-firewall"
