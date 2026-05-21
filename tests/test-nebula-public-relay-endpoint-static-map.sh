#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/input-path.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

labs_path="$(resolve_input_path "${repo_root}" network-labs)"
intent_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/intent.nix"
inventory_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/inventory.nix"

nix eval --impure --no-warn-dirty --json --expr '
  let
    repo = "'"$repo_root"'";
    flake = builtins.getFlake (toString repo);
    system = "x86_64-linux";
    api = flake.libBySystem.${system}.renderer;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    plan = import (repo + "/tests/nix/nebula-plan-from-inputs.nix") {
      repoRoot = repo;
      intentPath = "'"$intent_path"'";
      inventoryPath = "'"$inventory_path"'";
      inherit system;
    };
    nodeName = "nixos-router-core-nebula";
    module = api.buildNebulaRuntimeNixosModule {
      inherit pkgs nodeName;
      runtimeNode = plan.nodes.${nodeName};
      externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
    };
    relayNodeName = "hetz-router-nebula-core";
    relayModule = api.buildNebulaRuntimeNixosModule {
      inherit pkgs;
      nodeName = relayNodeName;
      runtimeNode = plan.nodes.${relayNodeName};
    };
    relayDynamicModule = api.buildNebulaRuntimeNixosModule {
      inherit pkgs;
      nodeName = relayNodeName;
      runtimeNode = plan.nodes.${relayNodeName};
      externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
    };
  in
    {
      node = plan.nodes.${nodeName};
      relay = plan.nodes.${relayNodeName};
      network = module.services.nebula.networks.runtime;
      relayNetwork = relayModule.services.nebula.networks.runtime;
      relayDynamicPreStart = relayDynamicModule.systemd.services."nebula@runtime".preStart;
      preStart = module.systemd.services."nebula@runtime".preStart;
    }
' > "$tmp_dir/result.json"

jq -e '
  .node.relay.nodes == ["hetz-router-nebula-core"] and
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
  (.preStart | contains("/run/secrets/hetzner-public-ipv4")) and
  (.preStart | contains("static_host_map had no entries to replace for"))
' "$tmp_dir/result.json" >/dev/null || {
  echo "FAIL nebula-public-relay-endpoint-static-map: relayed runtime nodes must use explicit public endpoint secret static maps, not learned private underlay addresses" >&2
  jq . "$tmp_dir/result.json" >&2
  exit 1
}

echo "PASS nebula-public-relay-endpoint-static-map"
