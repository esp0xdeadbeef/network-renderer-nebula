# network-renderer-nebula

`network-renderer-nebula` emits Nebula runtime materialization from explicit
CPM overlay data and Nebula realization input.

It is a provider renderer, not a forwarding model.

Pipeline position: this repository is downstream of
`network-control-plane-model` and upstream of runtime consumers such as NixOS
or lab orchestration.

Migration, deviation, exception, transition, or temporary compatibility behavior
must be explicit in the README, tests, and owning layer before it is accepted.

```text
network-forwarding-model -> network-control-plane-model -> network-renderer-nebula
```

## Spec Chain

This renderer materializes Nebula runtime output from explicit CPM overlay data.
All behavior requirements originate from the FS-460 spec chain.

### Owning Chain: Remote Egress over Nebula

| Layer | ID | Description |
|-------|----|-------------|
| URS   | Via FS-460 | Provider overlay transport — explicit policy-routed path |
| FS    | FS-460 | Remote Egress over Nebula — explicit policy-routed path with fail-closed |
| HDS   | FS-460-HDS-010 | Nebula Remote Egress hardware design — substrate facts (peer ID, overlay readiness, egress surface) |
| SDS   | FS-460-HDS-010-SDS-010 | Nebula Remote Egress software design — architecture, failure boundaries, overlay identity preservation |
| SMS   | FS-460-HDS-010-SDS-010-SMS-010 | **Coordinator** — Nebula renderer module: container binary in nix store, persistent daemon (not bash wrapper), service name `s88-provider-interface-nebula1.service` (SMT: OK) |
| SMS   | FS-460-HDS-010-SDS-010-SMS-020 | Underlay-payload separation — Nebula bootstrap reachability ≠ tenant/payload reachability |
| SMS   | FS-460-HDS-010-SDS-010-SMS-030 | Overlay route metadata — every overlay route record carries overlay identity + concrete peer-site identity |
| SMS   | FS-460-HDS-010-SDS-010-SMS-040 | Default route denial — WAN egress must not be converted to Nebula overlay reachability |
| SMS   | FS-460-HDS-010-SDS-010-SMS-050 | Delegated public-egress default — remote public-egress via overlay path only when explicitly modeled |

### SMT Status (2026-06-12)

- FS-460-HDS-010-SDS-010-SMS-010 (Coordinator): **OK** — All child atoms tested at `network-renderer-nebula@805894b3`
- SMS-020 through SMS-050: **OK** — Full suite 25/25 passing
- All child SMS rows delegate to coordinator. Coordinator has no independent construction beyond child module contracts.

### Pipeline

```
network-labs (intent + inventory) → network-compiler → NFM → CPM → network-renderer-nebula
```

Required inputs: CPM bundle JSON (containing `nebulaRuntimePlan` or `controlPlane` plus `inventory`).
Inventory is a required input per SMS-010 — the pipeline must include it.

### SMS-010 Key Requirements

- Container definition MUST include `nebula` binary in nix store closure
- Persistent systemd service required (no bash wrapper that exits)
- Service name: `s88-provider-interface-nebula1.service`

### Owning Repository

Construction tests: `network-renderer-nebula/tests/`

## Contract

- The forwarding model and CPM are the source of truth.
- CPM decides overlay ownership, termination, prefixes, policy, and public-exit
  semantics.
- This renderer consumes explicit Nebula input and emits Nebula runtime output.
- Missing, partial, or inconsistent Nebula input must fail evaluation.
- Renderer output must be deterministic for the same CPM/provider input.
- Consumers must wire the emitted output; they must not derive Nebula semantics
  locally.

## Allowed

- Render Nebula runtime plans.
- Render node identities, overlay addresses, groups, lighthouse data, unsafe
  routes, service metadata, cert/signing inputs, and NixOS modules that enable
  Nebula itself.
- Render external lighthouse validation host material from explicit runtime
  values supplied before evaluation.
- Emit Nebula-owned public-ingress runtime facts for the lighthouse service and
  compatible public services with concrete CPM provider endpoints. Public
  ingress for another provider class is reported as unsupported in the runtime
  facts and remains owned by that provider renderer.

## Not Allowed

- Decide forwarding policy, tenant reachability, overlay termination, public
  exit, DNS behavior, or prefix ownership.
- Open host firewalls, install nftables policy, enable kernel forwarding, or
  otherwise make host/router reachability decisions for consumers.
- Guess Nebula routes, addresses, lighthouses, or groups from names.
- Patch missing unsafe routes after boot.
- Require `network-renderer-nixos` or `s-router-test` to reinterpret Nebula
  provider semantics.
- Materialize WireGuard, OpenVPN, or other non-Nebula provider public ingress
  through Nebula runtime facts.

## API

The flake exports:

- `libBySystem.<system>.renderer.buildNebulaPlan`
- `libBySystem.<system>.renderer.buildNebulaBootstrapSpec`
- `libBySystem.<system>.renderer.buildNebulaBootstrapNixosModule`
- `libBySystem.<system>.renderer.buildExternalLighthouseNixosModule`
- `libBySystem.<system>.renderer.buildNebulaRuntimeNixosModule`

The flake also exports a CLI for standalone runtime-node materialization from
explicit CPM/provider data:

```bash
nix run github:esp0xdeadbeef/network-renderer-nebula -- \
  render-node --cpm ./cpm-bundle.json --node b-router-core-nebula
```

`--cpm` must point to JSON containing either `nebulaRuntimePlan`, or
`controlPlane`/`control_plane_model` plus `inventory`. If inventory is kept in a
separate JSON file, pass `--inventory ./inventory.json`.

Unmanaged members such as laptops may be rendered only with explicit overlay and
address input:

```bash
nix run github:esp0xdeadbeef/network-renderer-nebula -- \
  render-node --cpm ./cpm-bundle.json --node laptop-01 --extra-node \
  --overlay espbranch::site-b::east-west \
  --addr4 100.96.10.77/24 --addr6 fd42:dead:beef:ee::77/64
```

This does not grant forwarding, unsafe routes, public exit, host firewall
policy, or DNS behavior. It only renders an explicit Nebula member.

## Tests

Run:

```bash
bash tests/test-nebula-plan.sh
bash tests/test-nebula-bootstrap-module.sh
bash tests/test-cli-render-node.sh
```
