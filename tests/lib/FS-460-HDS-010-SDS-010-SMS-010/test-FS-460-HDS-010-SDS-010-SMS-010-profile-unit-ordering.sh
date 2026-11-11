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

  # Both providers are required, not either. The first attempt at this fix named
  # only `sops-install-secrets.service`; on the HAT substrate that unit is
  # `not-found`, so the edge was a no-op, the profile unit still raced the
  # fixture unit `isp-fake-secrets.service`, and the failure was identical.
  # Asserting one-of them would have let that defective fix pass.
  needs = name: lib.all (dep: builtins.elem dep (profileUnits.${name}.after or [ ]))
    [ "sops-install-secrets.service" "isp-fake-secrets.service" ];

in
  require (profileUnits != { })
    "expected the module to generate at least one nebula-profile-* unit; it generated none, so this case would assert nothing"
  && require (builtins.all needs (builtins.attrNames profileUnits))
     ("every nebula-profile-* unit must be ordered after BOTH " +
      "sops-install-secrets.service (a host with sops-nix) and " +
      "isp-fake-secrets.service (the HAT fixture, which writes the plaintext " +
      "secrets); a unit that does not exist is a no-op `after`, so naming only " +
      "one leaves the race in place on the other substrate. " +
      "Got: " + builtins.concatStringsSep "; " (map describe (builtins.attrNames profileUnits)))
' >/dev/null

echo "PASS profile-unit-ordering"
