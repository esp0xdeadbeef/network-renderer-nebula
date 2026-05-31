#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-006-SMS-001-004
# GAMP-ID: USR-MODEL-001-FS-001-HDS-004-SDS-001-006-SMS-001-CMC-001-004
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_json="$(mktemp)"
trap 'rm -f "${tmp_json}"' EXIT

nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString '"$repo_root"');
  api = flake.libBySystem.x86_64-linux.renderer;
in
api.buildNebulaPublicIngressRuntimeFacts {
  hostName = "validator-host";
  lighthousePublicIPv4SecretPath = "/run/secrets/relay-public-ipv4";
  runtimePublicIPv4SecretPath = "/run/secrets/runtime-public-ipv4";
  runtimeContainerName = "edge-nebula";
  runtimeNode.service.listenHost = "172.31.254.4";
  runtimeNode.service.port = 443;
  hostNatIngressTargetWan = {
    hostAddress4 = "172.31.254.1/24";
    hostGateway4 = "172.31.254.1";
    coreAddress4Bare = "172.31.254.3";
  };
  inventory.realization.nodes.edge-nebula = {
    host = "validator-host";
    logicalNode = {
      enterprise = "acme";
      site = "edge";
      name = "edge-nebula";
    };
  };
  forwarding.enterprise.acme.site.edge.hostNatIngress = {
    hostReservedPorts = [
      {
        proto = "tcp";
        dports = [ 22 ];
      }
    ];
  };
  controlPlane.control_plane_model.data.acme.edge.services = [
    {
      name = "relay-nebula";
      trafficType = "nebula";
      providerEndpoints = [
        {
          ipv4 = [ "10.90.10.100" ];
        }
      ];
    }
    {
      name = "client-https";
      trafficType = "tcp-443";
      providerEndpoints = [
        {
          ipv4 = [ "10.90.20.10" ];
        }
      ];
    }
  ];
  controlPlane.control_plane_model.data.acme.edge.relations = [
    {
      action = "allow";
      from = {
        kind = "external";
        name = "wan";
      };
      to = {
        kind = "service";
        name = "client-https";
      };
    }
  ];
}
' >"${tmp_json}"

jq -e '
  .localLighthouseEndpoint4 == "10.90.10.100" and
  .publicIngress.snatSourceCidr4 == "172.31.254.1/24" and
  .publicIngress.services.acme.edge."relay-nebula".publicIPv4SecretPath == "/run/secrets/relay-public-ipv4" and
  .publicIngress.services.acme.edge."relay-nebula".gateway4 == "172.31.254.3" and
  .publicIngress.services.acme.edge."client-https".publicIPv4SecretPath == "/run/secrets/relay-public-ipv4" and
  .publicIngress.services.acme.edge."client-https".gateway4 == "172.31.254.3" and
  .publicIngress.runtimeForwards[0].publicIPv4SecretPath == "/run/secrets/runtime-public-ipv4" and
  .publicIngress.runtimeForwards[0].targetIPv4 == "172.31.254.4" and
  .publicIngress.runtimeForwards[0].exceptTcpDports == [22] and
  .publicIngress.runtimeForwards[0].containerInterface.container == "edge-nebula" and
  .publicIngress.runtimeForwards[0].inputDports == [443] and
  .publicIngress.runtimeForwards[0].containerInterface.inputDports == [443]
' "${tmp_json}" >/dev/null

echo "PASS public-ingress-runtime-facts"
