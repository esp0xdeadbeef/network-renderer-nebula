#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nix eval --impure --no-warn-dirty --expr '
let
  flake = builtins.getFlake (toString '"$repo_root"');
  system = builtins.currentSystem;
  api = flake.libBySystem.${system}.renderer;
  pkgs = import flake.inputs.nixpkgs { inherit system; };
  lib = pkgs.lib;
  controlPlane = {
    control_plane_model.data.acme.lab = {
      runtimeTargets = {
        lab-lighthouse = {
          placement.host = "s-router-nixos";
          logicalNode = {
            enterprise = "acme";
            site = "lab";
            name = "lab-lighthouse";
          };
          containers = [
            {
              name = "default";
              container = "lab-lighthouse";
            }
          ];
        };
        lab-client-nebula = {
          placement.host = "s-router-nixos";
          logicalNode = {
            enterprise = "acme";
            site = "lab";
            name = "lab-client-nebula";
          };
          containers = [
            {
              name = "default";
              container = "lab-client-nebula";
            }
          ];
        };
      };
      overlays.nebula-layer-entry = {
        provider = "nebula";
        nodes = {
          lab-lighthouse = {
            addr4 = "100.96.90.1/24";
            addr6 = "fd42:dead:90::1/64";
          };
          lab-client-nebula = {
            addr4 = "100.96.90.2/24";
            addr6 = "fd42:dead:90::2/64";
          };
        };
        nebula.lighthouse = {
          node = "lab-lighthouse";
          endpoint = "198.51.100.90";
          endpoint6 = "2001:db8:90::90";
          port = 4242;
        };
        runtimeNodes = {
          lab-lighthouse = {
            service = {
              name = "nebula-layer-entry";
              interface = "nebula1";
              listenHost = "100.96.90.1";
              port = 4242;
              mtu = 1300;
            };
            groups = [ "lighthouse" ];
            relay.amRelay = true;
          };
          lab-client-nebula = {
            service = {
              name = "nebula-layer-entry";
              interface = "nebula1";
              listenHost = "100.96.90.2";
              port = 4242;
              mtu = 1300;
            };
            groups = [ "client" ];
            relay = {
              useRelays = true;
              relays = [ "lab-lighthouse" ];
            };
          };
        };
      };
    };
  };
  nixosModule = api.hostModule {
    inherit controlPlane;
    hostName = "s-router-nixos";
  };
  clabModule = api.hostModule {
    inherit controlPlane;
    hostName = "s-router-clab";
  };
  output = nixosModule { config = {}; inherit lib pkgs; };
  clabOutput = clabModule { config = {}; inherit lib pkgs; };
  require = cond: msg: if cond then true else throw msg;
  clientDir = "/persist/nebula-runtime/profiles/lab-client-nebula";
  lighthouseDir = "/persist/nebula-runtime/profiles/lab-lighthouse";
  clientKeySecret = "/run/secrets/nebula-profile-lab-client-nebula-key";
  clientCrtSecret = "/run/secrets/nebula-profile-lab-client-nebula-crt";
  clientCaSecret = "/run/secrets/nebula-profile-lab-client-nebula-ca-crt";
  lighthouseKeySecret = "/run/secrets/nebula-profile-lab-lighthouse-key";
  lighthouseCrtSecret = "/run/secrets/nebula-profile-lab-lighthouse-crt";
  lighthouseCaSecret = "/run/secrets/nebula-profile-lab-lighthouse-ca-crt";
in
  require (builtins.attrNames output.containers == [ "lab-client-nebula" "lab-lighthouse" ]) "hostModule must materialize hosted Nebula containers"
  && require (output.containers.lab-client-nebula.bindMounts.${clientDir}.hostPath == clientDir) "client profile bind mount host path mismatch"
  && require (output.containers.lab-client-nebula.bindMounts.${clientDir}.isReadOnly == true) "client profile bind mount must be read-only"
  && require (output.containers.lab-client-nebula.bindMounts.${clientKeySecret}.hostPath == clientKeySecret) "client key secret bind mount host path mismatch"
  && require (output.containers.lab-client-nebula.bindMounts.${clientCrtSecret}.hostPath == clientCrtSecret) "client cert secret bind mount host path mismatch"
  && require (output.containers.lab-client-nebula.bindMounts.${clientCaSecret}.hostPath == clientCaSecret) "client CA secret bind mount host path mismatch"
  && require (output.containers.lab-client-nebula.bindMounts.${clientKeySecret}.isReadOnly == true) "client key secret bind mount must be read-only"
  && require (output.containers.lab-client-nebula.bindMounts.${clientCrtSecret}.isReadOnly == true) "client cert secret bind mount must be read-only"
  && require (output.containers.lab-client-nebula.bindMounts.${clientCaSecret}.isReadOnly == true) "client CA secret bind mount must be read-only"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseDir}.hostPath == lighthouseDir) "lighthouse profile bind mount host path mismatch"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseDir}.isReadOnly == true) "lighthouse profile bind mount must be read-only"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseKeySecret}.hostPath == lighthouseKeySecret) "lighthouse key secret bind mount host path mismatch"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseCrtSecret}.hostPath == lighthouseCrtSecret) "lighthouse cert secret bind mount host path mismatch"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseCaSecret}.hostPath == lighthouseCaSecret) "lighthouse CA secret bind mount host path mismatch"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseKeySecret}.isReadOnly == true) "lighthouse key secret bind mount must be read-only"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseCrtSecret}.isReadOnly == true) "lighthouse cert secret bind mount must be read-only"
  && require (output.containers.lab-lighthouse.bindMounts.${lighthouseCaSecret}.isReadOnly == true) "lighthouse CA secret bind mount must be read-only"
  && require (builtins.elem "d /persist/nebula-runtime 0700 root root -" output.systemd.tmpfiles.rules) "host tmpfiles must create Nebula runtime root"
  && require (builtins.elem "d /persist/nebula-runtime/profiles 0700 root root -" output.systemd.tmpfiles.rules) "host tmpfiles must create Nebula profile root"
  && require (builtins.elem "d /persist/nebula-runtime/profiles/lab-client-nebula 0700 root root -" output.systemd.tmpfiles.rules) "host tmpfiles must create client profile directory"
  && require (builtins.elem "d /persist/nebula-runtime/profiles/lab-lighthouse 0700 root root -" output.systemd.tmpfiles.rules) "host tmpfiles must create lighthouse profile directory"
  && require ((clabOutput.containers or { }) == { }) "non-owning host must not materialize Nebula containers"
  && require ((clabOutput.systemd.tmpfiles.rules or [ ]) == [ ]) "non-owning host must not create Nebula profile directories"
' >/dev/null

echo "PASS host-profile-bindmounts"
