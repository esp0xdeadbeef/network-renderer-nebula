# network-renderer-nebula Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Architecture Shape

- state=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=renderer code must stay in s88-style responsibility folders; top-level files are limited to flakes, tests, scripts/entrypoints, and thin imports into the renderer structure.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete renderer responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.

## Live Lab Failures

- state=still-broken | target=delegated public egress unsafe routes | evidence=2026-05-13 s-router-test hostile-node01 IPv6 ping to 2606:4700:4700::1111 failed with hop-limit exceeded from fd42:dead:beef:ee::3; Hetzner c-router-nebula-core installed ::/1 and 8000::/1 on nebula1 and selected nebula1 for the public route from hostile delegated GUA | reason=the renderer materializes delegated-public-egress split defaults on the site-C exit node instead of only on the remote entry side, creating an overlay loop.
- state=still-broken | target=delegated hostile IPv4 public egress | evidence=2026-05-13 s-router-test hostile-node01 ping to 1.1.1.1 failed while the endpoint default pointed to b-router-access-hostile; route ownership is still under investigation | reason=must be classified separately from the IPv6 Nebula loop before marking hostile public egress production-safe.
