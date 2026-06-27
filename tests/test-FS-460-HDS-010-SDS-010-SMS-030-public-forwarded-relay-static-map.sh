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
    nodeName = "relay-core";
    module = api.buildNebulaRuntimeNixosModule {
      inherit pkgs nodeName;
      runtimeNode = {
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
        };
        staticHostMap = {
          "100.96.10.254" = [ "198.51.100.10:4242" ];
          "fd42:dead:beef:ee::254" = [ "[2001:db8:51::10]:4242" ];
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
    };
  in
    module.services.nebula.networks.runtime
' > "$tmp_dir/network.json"

jq -e '
  .listen.host == "172.31.254.4" and
  .listen.port == 4243 and
  .staticHostMap["100.96.10.254"] == ["198.51.100.10:4242"] and
  .staticHostMap["fd42:dead:beef:ee::254"] == ["[2001:db8:51::10]:4242"] and
  .isRelay == true and
  .settings.relay.am_relay == true and
  ([.firewall.inbound[]? | select(has("local_cidr") | not)] | length) == 0 and
  ([.firewall.outbound[]? | select(has("local_cidr") | not)] | length) == 0 and
  ([.firewall.inbound[]? | select(.local_cidr == "10.90.10.0/24")] | length) == 1 and
  ([.firewall.inbound[]? | select(.local_cidr == "fd42:dead:cafe:10::/64")] | length) == 1
' "$tmp_dir/network.json" >/dev/null

source_file="${repo_root}/s88/Enterprise/runtime/nixos-module.nix"
! grep -F '.[$n].lighthouse.node == $n' "$source_file" >/dev/null
! grep -F 'profile-bootstrap.bash' "$source_file" >/dev/null

echo "PASS test-nebula-public-forwarded-relay-static-map"
