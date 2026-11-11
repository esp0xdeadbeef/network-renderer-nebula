#!/usr/bin/env bash
set -euo pipefail
#
# The Nebula PKI profile units read their material from /run/secrets, which
# another unit writes. They must be ordered after it.
#
# Measured 2026-11-11 on the cobalt HAT (nixos-shell substrate): the unit
# declared no ordering edge against the secret writer, ran first, and failed
#
#   install: cannot stat '/run/secrets/nebula-profile-core-vpn-garnet-cobalt-ca-crt'
#
# The service is `oneshot` with no `Restart=`, so it was never retried: the
# guest finished booting in `degraded` state with no Nebula PKI, and only a
# manual `systemctl restart` produced `active`. A missing secret would have
# failed the restart too, which is what identifies this as ordering.
#
# The writer is `sops-install-secrets.service` -- the same unit the platform
# already orders against elsewhere
# (nixos/virtual-machine/nixos-shell-vm/wifi-ap.nix).
#
# This case is the static half: every generated profile unit names the writer
# in `after`. The dynamic half (a live boot with a populated /run/secrets) is
# the HAT itself.

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

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
          logicalNode = { enterprise = "acme"; site = "lab"; name = "lab-lighthouse"; };
          containers = [ { name = "default"; container = "lab-lighthouse"; } ];
        };
        lab-client-nebula = {
          placement.host = "s-router-nixos";
          logicalNode = { enterprise = "acme"; site = "lab"; name = "lab-client-nebula"; };
          containers = [ { name = "default"; container = "lab-client-nebula"; } ];
        };
      };
      overlays.nebula-layer-entry = {
        provider = "nebula";
        nodes = {
          lab-lighthouse = { addr4 = "100.96.90.1/24"; addr6 = "fd42:dead:90::1/64"; };
          lab-client-nebula = { addr4 = "100.96.90.2/24"; addr6 = "fd42:dead:90::2/64"; };
        };
        nebula.lighthouse = {
          node = "lab-lighthouse";
          endpoint = "198.51.100.90";
          endpoint6 = "2001:db8:90::90";
        };
      };
    };
  };
  nixosModule = api.hostModule {
    inherit controlPlane;
    hostName = "s-router-nixos";
  };
  output = nixosModule { config = {}; inherit lib pkgs; };
  require = cond: msg: if cond then true else throw msg;

  # Every service this module generates that materializes a profile must be
  # ordered after the unit that writes /run/secrets.
  profileUnits = lib.filterAttrs
    (name: _: lib.hasPrefix "nebula-profile-" name)
    output.systemd.services;

  describe = name:
    let svc = profileUnits.${name};
    in "${name}: after=${builtins.toJSON (svc.after or [ ])}";

in
  require (profileUnits != { })
    "expected the module to generate at least one nebula-profile-* unit; it generated none, so this case would assert nothing"
  && require (builtins.all
       (name: builtins.elem "sops-install-secrets.service" (profileUnits.${name}.after or [ ]))
       (builtins.attrNames profileUnits))
     ("every nebula-profile-* unit must be ordered after sops-install-secrets.service, " +
      "the unit that writes /run/secrets, otherwise it can run first, fail once " +
      "and never be retried (oneshot, no Restart=). " +
      "Got: " + builtins.concatStringsSep "; " (map describe (builtins.attrNames profileUnits)))
' >/dev/null

echo "PASS profile-unit-ordering"
