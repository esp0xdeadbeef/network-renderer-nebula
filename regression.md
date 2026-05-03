# network-renderer-nebula Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Architecture Shape

- state=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=renderer code must stay in s88-style responsibility folders; top-level files are limited to flakes, tests, scripts/entrypoints, and thin imports into the renderer structure.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete renderer responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.
