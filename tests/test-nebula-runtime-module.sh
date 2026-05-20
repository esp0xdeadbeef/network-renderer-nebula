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
      externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
      runtimeNode = {
        groups = [ "lab" "core" ];
        lighthouse = {
          node = "c-router-lighthouse";
          overlayIps = [ "100.96.10.254" "fd42:dead:beef:ee::254" ];
          endpoints = [ "198.51.100.10:4242" "[2001:db8:51::10]:4242" ];
          port = "4242";
        };
        relay = {
          amRelay = false;
          useRelays = true;
          relays = [ "100.96.10.3" ];
        };
        service = {
          interface = "nebula1";
          name = "nebula-runtime";
        };
        overlayAddresses = [
          "100.96.10.2/24"
          "fd42:dead:beef:ee::2/64"
        ];
        routePreparation = {
          removeRoutes = [ "10.20.10.0/24" ];
          overlayHosts = [ "100.96.10.254" ];
          underlayEndpoints = [ "198.51.100.10" ];
        };
        dynamicFirewallCidrs = [
          {
            sourceFile = "/run/secrets/access-node-ipv6-prefix-hostile";
            family = "ipv6";
          }
        ];
        dynamicUnsafeRoutes = [
          {
            sourceFile = "/run/secrets/access-node-ipv6-prefix-branch-hostile";
            family = "ipv6";
            via6 = "fd42:dead:beef:ee::2";
          }
        ];
        unsafeRoutes = [
          {
            route = "10.20.10.0/24";
            via4 = "100.96.10.2";
            install = true;
          }
        ];
        nebulaNetwork = {
          settings = {
            nebulaFirewallRules = {
              inbound = [
                {
                  port = "any";
                  proto = "any";
                  host = "any";
                }
              ];
              outbound = [
                {
                  port = "any";
                  proto = "any";
                  host = "any";
                }
              ];
            };
            tun.unsafe_routes = [
              {
                route = "10.20.10.0/24";
                via = "100.96.10.2";
                mtu = 1200;
                install = true;
              }
            ];
          };
        };
      };
    };
    lighthouseModule = api.buildNebulaRuntimeNixosModule {
      inherit pkgs;
      nodeName = "c-router-lighthouse";
      externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
      runtimeNode = {
        groups = [ "lab" "lighthouse" ];
        lighthouse = {
          node = "c-router-lighthouse";
          overlayIps = [ "100.96.10.254" "fd42:dead:beef:ee::254" ];
          endpoints = [ "198.51.100.10:4242" "[2001:db8:51::10]:4242" ];
          port = "4242";
        };
        relay = {
          amRelay = false;
          useRelays = false;
          relays = [ ];
        };
        service = {
          interface = "nebula1";
          name = "nebula-runtime";
        };
        overlayAddresses = [
          "100.96.10.254/24"
          "fd42:dead:beef:ee::254/64"
        ];
        nebulaNetwork = {
          settings.nebulaFirewallRules = {
            inbound = [ ];
            outbound = [ ];
          };
        };
      };
    };
    service = module.systemd.services."nebula@runtime";
    lighthouseService = lighthouseModule.systemd.services."nebula@runtime";
    network = module.services.nebula.networks.runtime;
  in
  {
    tmpfiles = module.systemd.tmpfiles.rules;
    firewall = module.networking.firewall;
    nftablesRuleset = module.networking.nftables.ruleset;
    inherit network service lighthouseService;
  }
' > "$tmp_dir/runtime-module.json"

jq -e '
  (.tmpfiles | index("d /persist/nebula-runtime 0700 root root -") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime/profiles 0700 root root -") != null) and
  (.tmpfiles | index("d /persist/nebula-runtime/profiles/b-router-core-nebula 0700 root root -") != null) and
  (.firewall.extraInputRules | contains("s88-nebula-runtime-input")) and
  (.firewall.extraInputRules | contains("udp dport 4242 accept")) and
  (.firewall.extraInputRules | contains("s88-nebula-runtime-listen")) and
  (.firewall.extraForwardRules | contains("s88-nebula-runtime-forward-in")) and
  (.firewall.extraForwardRules | contains("s88-nebula-runtime-forward-out")) and
  (.nftablesRuleset.content | contains("insert rule inet router input iifname \"nebula1\"")) and
  (.nftablesRuleset.content | contains("insert rule inet router input udp dport 4242 accept")) and
  (.nftablesRuleset.content | contains("insert rule inet router forward iifname \"nebula1\"")) and
  (.nftablesRuleset.content | contains("insert rule inet router forward oifname \"nebula1\"")) and
  .network.ca == "/persist/nebula-runtime/profiles/b-router-core-nebula/ca.crt" and
  .network.cert == "/persist/nebula-runtime/profiles/b-router-core-nebula/b-router-core-nebula.crt" and
  .network.key == "/persist/nebula-runtime/profiles/b-router-core-nebula/b-router-core-nebula.key" and
  .network.staticHostMap["100.96.10.254"][0] == "198.51.100.10:4242" and
  (.network.lighthouses | index("100.96.10.254") != null) and
  .network.tun.device == "nebula1" and
  .network.settings.static_map.network == "ip" and
  .network.settings.tun.unsafe_routes[0].route == "10.20.10.0/24"
' "$tmp_dir/runtime-module.json" >/dev/null

jq -e '
  (.service.unitConfig.AssertPathExists | index("/persist/nebula-runtime/profiles/b-router-core-nebula/ca.crt") != null) and
  (.service.unitConfig.AssertPathExists | index("/persist/nebula-runtime/profiles/b-router-core-nebula/b-router-core-nebula.crt") != null) and
  (.service.unitConfig.AssertPathExists | index("/persist/nebula-runtime/profiles/b-router-core-nebula/b-router-core-nebula.key") != null) and
  (.service.preStart | contains("ip link delete")) and
  (.service.preStart | contains("ip address delete")) and
  (.service.preStart | contains("/run/secrets/hetzner-lighthouse-public-ipv4")) and
  (.service.preStart | contains("/run/secrets/access-node-ipv6-prefix-hostile")) and
  (.service.preStart | contains("/run/secrets/access-node-ipv6-prefix-branch-hostile")) and
  (.service.preStart | contains("install -m 0600 /etc/nebula/runtime.yml /run/nebula-runtime/runtime.yml")) and
  (.service.preStart | contains("unsafe_routes: []")) and
  (.service.preStart | contains("local_cidr")) and
  (.service.preStart | contains("unsafe_routes")) and
  (.service.preStart | contains("/run/nebula-runtime/runtime.yml")) and
  (.service.serviceConfig.ExecStart.content.content | contains("/run/nebula-runtime/runtime.yml")) and
  .service.serviceConfig.User.content == "root" and
  .service.serviceConfig.Group.content == "root"
' "$tmp_dir/runtime-module.json" >/dev/null

jq -e '
  (.lighthouseService.preStart | contains("ip link delete")) and
  (.lighthouseService.preStart | contains("static_host_map had no lighthouse entries to replace") | not) and
  (.lighthouseService.preStart | contains("/run/secrets/hetzner-lighthouse-public-ipv4") | not) and
  .lighthouseService.serviceConfig.ExecStart.condition == false
' "$tmp_dir/runtime-module.json" >/dev/null

source_file="${repo_root}/s88/Enterprise/runtime/nixos-module.nix"
grep -F 'services.nebula.networks.${networkName}' "$source_file" >/dev/null
! grep -F 'nebula-runtime-prepare-underlay-routes' "$source_file" >/dev/null
! grep -F 'route-preparation.json' "$source_file" >/dev/null
! grep -F 'ip route replace "$endpoint/32"' "$source_file" >/dev/null
! grep -F 'ip -6 route replace "$endpoint/128"' "$source_file" >/dev/null
! grep -F 'grep -E' "$source_file" >/dev/null

echo "PASS test-nebula-runtime-module"
