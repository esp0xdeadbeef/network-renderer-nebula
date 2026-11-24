# network-renderer-nebula S88 Boundary

`network-renderer-nebula` owns the projection of a validated canonical
realization bundle into Nebula overlay configuration
(FS-460-HDS-010-SDS-010-SMS-010 and its child rows). The bundle carries the
released `network-control-plane-artifact`; the renderer reads the enterprise,
site and overlay facts inside it and never reads raw intent, inventory, or
forwarding-model output.

## Enterprise

The renderer consumes the enterprise scope the bundle already carries
(`canonicalSites.byEnterprise`). It does not choose an enterprise, and it does
not infer one from a hostname or a site name: a missing enterprise or site
record is a hard failure, because a silently empty overlay is a site with no
tunnel (FS-310-HDS-010-SDS-010-SMS-120).

`Enterprise/default.nix` is the facade. Everything below it is reached from
there or from the CLI, and nothing below it reaches up a level.

## Site

Site-level overlay facts -- which overlays exist, which nodes terminate them,
the provider bootstrap DNS -- are read from the bundle's canonical site records
(`canonical-site-tree.nix`). `overlay-plan.nix` turns those records into a
runtime plan; `overlay-entries.nix` and `relay-resolution.nix` resolve peers and
lighthouses. Nothing here re-derives a provider fact the model already states.

## Unit

Runtime-target projection lives in `runtime-nodes.nix`, `node-merge.nix`,
`runtime/nixos-module.nix`, and `runtime-container-name.nix`. Route, unsafe-route
and firewall-CIDR projection lives in `derived-runtime-routes.nix`,
`derived-dynamic-unsafe-routes.nix`, and `derived-dynamic-firewall-cidrs.nix`,
all of which read CPM-emitted values and fail closed rather than defaulting.

## ControlModule

The NixOS module that instantiates the overlay on a host --
`bootstrap/nixos-module.nix` and its `nixos-module/` children -- plus secret
mount naming (`runtime-secret-mounts.nix`, `delegated-prefix-secret-names.nix`)
and public-ingress facts (`public-ingress-*.nix`, `host-nat-ingress-target.nix`).
This is the only level that emits a systemd unit or a NixOS option.

## Phase / EquipmentModule

Not present. A Nebula overlay has no equipment or process structure of its own;
the renderer emits configuration for a host and stops there.

## Entrypoints

- `flake.nix` -- `libBySystem.*.renderer.canonical.hostModule` and the package.
- `bin/network-renderer-nebula` -- the CLI, whose `render-node` command imports
  `s88/Enterprise/cli/render-node.nix`. The import is a Nix expression embedded
  in a shell string, so a scanner that only reads `.nix` files sees that module
  as unreachable; the S88 graph test reads `bin/` for exactly this reason.

## Known open defect

23 throws across `s88/Enterprise/` cite `FS-310-HDS-010-SDS-010-SMS-110`, which
does not exist in the platform tree. That is recorded, with the evidence and the
reproduction, in `BUG-7ad46731-be05-4e8e-b923-c4404d0d0c60.md`. It is not fixed
here: the fix is a specification decision (add the row, or cite the row that
owns the contract), not a citation edit.
