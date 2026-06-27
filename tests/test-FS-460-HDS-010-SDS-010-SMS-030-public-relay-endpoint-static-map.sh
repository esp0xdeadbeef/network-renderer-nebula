#!/usr/bin/env bash
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-030
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

nix eval --impure --no-warn-dirty --json --expr '
  let
    flake = builtins.getFlake ("path:'"${repo_root}"'");
    system = "x86_64-linux";
    api = flake.libBySystem.${system}.renderer;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    nodeName = "home-core";
    relayNodeName = "edge-relay";
    relayRuntimeNode = {
      overlayAddresses = [ "100.96.10.3/24" "fd42:dead:beef:ee::3/64" ];
      groups = [ "relay" "core" ];
      lighthouse = {
        node = "remote-lighthouse";
        port = 4242;
        overlayIps = [ "100.96.10.254" "fd42:dead:beef:ee::254" ];
        endpoints = [ "198.51.100.10:4242" ];
      };
      relay = {
        amRelay = true;
        useRelays = false;
        relays = [ ];
        nodes = [ ];
      };
      service = {
        interface = "nebula1";
        name = "nebula-runtime";
        listenHost = "172.31.254.4";
        port = 4243;
        mtu = 1200;
        publicEndpoints = [
          {
            endpointSourceFile = "/run/secrets/hetzner-public-ipv4";
            port = 4243;
          }
        ];
      };
      staticHostMap = {
        "100.96.10.254" = [ "198.51.100.10:4242" ];
      };
      nebulaNetwork.settings.nebulaFirewallRules = {
        inbound = [
          { host = "any"; local_cidr = "10.90.10.0/24"; port = "any"; proto = "any"; }
          { host = "any"; local_cidr = "fd42:dead:cafe:10::/64"; port = "any"; proto = "any"; }
        ];
        outbound = [
          { host = "any"; local_cidr = "10.90.10.0/24"; port = "any"; proto = "any"; }
          { host = "any"; local_cidr = "fd42:dead:cafe:10::/64"; port = "any"; proto = "any"; }
        ];
      };
    };
    nodeRuntimeNode = {
      overlayAddresses = [ "100.96.10.1/24" "fd42:dead:beef:ee::1/64" ];
      groups = [ "core" ];
      lighthouse = {
        node = "remote-lighthouse";
        port = 4242;
        overlayIps = [ "100.96.10.254" "fd42:dead:beef:ee::254" ];
        endpoints = [ "198.51.100.10:4242" ];
      };
      relay = {
        amRelay = false;
        useRelays = true;
        relays = [ "100.96.10.3" ];
        nodes = [ relayNodeName ];
      };
      service = {
        interface = "nebula1";
        name = "nebula-runtime";
        listenHost = "100.96.10.1";
        port = 4242;
        mtu = 1200;
      };
      staticHostMap = {
        "100.96.10.3" = [ "127.0.0.1:4243" ];
        "100.96.10.254" = [ "198.51.100.10:4242" ];
      };
      staticHostMapSecretEndpoints = {
        "100.96.10.3" = [
          {
            sourceFile = "/run/secrets/hetzner-public-ipv4";
            port = "4243";
          }
        ];
      };
      nebulaNetwork.settings.nebulaFirewallRules = {
        inbound = [ ];
        outbound = [ ];
      };
    };
    module = api.buildNebulaRuntimeNixosModule {
      inherit pkgs nodeName;
      runtimeNode = nodeRuntimeNode;
      externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
    };
    relayModule = api.buildNebulaRuntimeNixosModule {
      inherit pkgs;
      nodeName = relayNodeName;
      runtimeNode = relayRuntimeNode;
    };
    relayDynamicModule = api.buildNebulaRuntimeNixosModule {
      inherit pkgs;
      nodeName = relayNodeName;
      runtimeNode = relayRuntimeNode;
      externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
    };
  in
    {
      node = nodeRuntimeNode;
      relay = relayRuntimeNode;
      network = module.services.nebula.networks.runtime;
      relayNetwork = relayModule.services.nebula.networks.runtime;
      relayDynamicPreStart = relayDynamicModule.systemd.services."nebula@runtime".preStart;
      preStart = module.systemd.services."nebula@runtime".preStart;
    }
' > "$tmp_dir/result.json"

jq -e '
  .node.relay.nodes == ["edge-relay"] and
  .node.relay.relays == ["100.96.10.3"] and
  .node.staticHostMap["100.96.10.3"] == ["127.0.0.1:4243"] and
  .node.staticHostMapSecretEndpoints["100.96.10.3"] == [
    {
      "port": "4243",
      "sourceFile": "/run/secrets/hetzner-public-ipv4"
    }
  ] and
  .relay.service.port == 4243 and
  .relay.service.listenHost == "172.31.254.4" and
  .relay.service.publicEndpoints[0].endpointSourceFile == "/run/secrets/hetzner-public-ipv4" and
  .relayNetwork.listen.host == "172.31.254.4" and
  .relayNetwork.listen.port == 4243 and
  (.relayDynamicPreStart | contains("/run/secrets/hetzner-lighthouse-public-ipv4 /run/secrets/hetzner-public-ipv6 4243 172.31.254.4 4242 100.96.10.254")) and
  (.relayDynamicPreStart | contains("if endpoint6 and not is_ipv4_literal(listen_host):")) and
  ([.relayNetwork.firewall.inbound[]? | select(has("local_cidr") | not)] | length) == 0 and
  ([.relayNetwork.firewall.outbound[]? | select(has("local_cidr") | not)] | length) == 0 and
  ([.relayNetwork.firewall.inbound[]? | select(.local_cidr == "10.90.10.0/24")] | length) == 1 and
  ([.relayNetwork.firewall.inbound[]? | select(.local_cidr == "fd42:dead:cafe:10::/64")] | length) == 1 and
  .network.staticHostMap["100.96.10.3"] == ["127.0.0.1:4243"] and
  .network.staticHostMap["100.96.10.254"][0] == "198.51.100.10:4242" and
  (.preStart | contains("/run/secrets/hetzner-public-ipv4")) and
  (.preStart | contains("static_host_map had no entries to replace for"))
' "$tmp_dir/result.json" >/dev/null || {
  echo "FAIL nebula-public-relay-endpoint-static-map: relayed runtime nodes must use explicit public endpoint secret static maps, not learned private underlay addresses" >&2
  jq . "$tmp_dir/result.json" >&2
  exit 1
}

echo "PASS nebula-public-relay-endpoint-static-map"
