# network-renderer-nebula

`network-renderer-nebula` emits Nebula runtime materialization exclusively from
CPM output. It consumes no raw intent, inventory, or forwarding-model files.

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
All behavior requirements originate from the FS-460 spec chain. Cross-cutting
renderer policy (CPM-only consumption, fail-closed, no naming inference) is
governed by FS-310.

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

### Cross-Cutting SMS (FS-310)

| Layer | ID | Description |
|-------|----|-------------|
| SMS   | FS-310-HDS-010-SDS-010-SMS-100 | Renderer CPM-only consumption — no raw intent/inventory reads |
| SMS   | FS-310-HDS-010-SDS-010-SMS-110 | Renderer fail-closed contract — throw on missing/ambiguous input |
| SMS   | FS-310-HDS-010-SDS-010-SMS-120 | Renderer no-naming-inference — never derive semantics from names |

### SMT Status (2026-06-13)

- FS-460-HDS-010-SDS-010-SMS-010 (Coordinator): **OK** — All child atoms tested at `network-renderer-nebula@6f2c6b8`
- SMS-020 through SMS-050: **OK** — Full suite 29/29 passing
- FS-310 SMS-100: **OK** — CPM-only consumption enforced; no --inventory CLI, no raw inventory walks
- All child SMS rows delegate to coordinator. Coordinator has no independent construction beyond child module contracts.

### Pipeline

```
network-labs (intent + inventory) → network-compiler → NFM → CPM → network-renderer-nebula
```

Required input: CPM output (single `controlPlane` attribute containing `control_plane_model` plus CPM-processed inventory). Per FS-983 and FS-310 SMS-100, the renderer consumes data exclusively through CPM's provider-neutral overlay output. No separate inventory file, no raw `inventory.nix` parsing, no upstream source file reads.

### SMS-010 Key Requirements

- Container definition MUST include `nebula` binary in nix store closure
- Persistent systemd service required (no bash wrapper that exits)
- Service name: `s88-provider-interface-nebula1.service`

### Owning Repository

Construction tests: `network-renderer-nebula/tests/` (run via `bash run-all-tests.sh`)

## Contract

- The forwarding model and CPM are the source of truth.
- CPM decides overlay ownership, termination, prefixes, policy, and public-exit
  semantics.
- This renderer consumes CPM output and emits Nebula runtime output.
- Missing, partial, or inconsistent CPM input must fail evaluation.
- Renderer output must be deterministic for the same CPM input.
- Consumers must wire the emitted output; they must not derive Nebula semantics
  locally.

## Allowed

- Render Nebula runtime plans from CPM output.
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

- Read `intent.nix`, `inventory.nix`, `inventory-nixos.nix`, or forwarding-model
  files directly (FS-310 SMS-100).
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

The flake exports as `libBySystem.<system>.renderer.<function>`:

**Core rendering:**
- `buildNebulaPlan` — produce a Nebula runtime plan from CPM output
- `hostModule` — primary NixOS host integration (accepts `controlPlane`, emits containers)
- `buildNebulaRuntimeNixosModule` — per-node NixOS module with Nebula daemon

**Bootstrap & lighthouse:**
- `buildNebulaBootstrapSpec` — bootstrap configuration from runtime plan
- `buildNebulaBootstrapNixosModule` — NixOS module for bootstrap daemon
- `buildExternalLighthouseNixosModule` — external lighthouse validation host module

**Hosting & runtime:**
- `selectHostedNebulaRuntimePlan` — filter plan to nodes hosted on a given host
- `selectDeploymentNebulaRuntimePlan` — filter plan to deployment-scoped nodes
- `runtimeContainerNameForHost` — resolve container name for a logical node on a host

**Public ingress & secrets:**
- `buildNebulaPublicIngressRuntimeFacts` — public-ingress facts for lighthouse/relay
- `selectHostNatIngressTarget` — NAT ingress target selection
- `delegatedPrefixSecretNames` — secret names for delegated prefixes
- `buildRuntimeSecretMounts` — secret mount paths for runtime nodes

The flake also exports a CLI for standalone runtime-node materialization from
explicit CPM data:

```bash
nix run github:esp0xdeadbeef/network-renderer-nebula -- \
  render-node --cpm ./cpm-bundle.json --node b-router-core-nebula
```

`--cpm` must point to JSON containing CPM's provider-neutral overlay output
(`controlPlane`/`control_plane_model` plus CPM-processed inventory). All data
reaches the renderer through CPM output — no separate inventory file is accepted.

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

Run the full auto-discovered test suite:

```bash
bash run-all-tests.sh
```

This discovers and runs all `tests/test-*.sh` files. Individual tests can be
run directly:

```bash
bash tests/test-nebula-plan.sh
bash tests/test-fs460-nebula-remote-egress-smt.sh
bash tests/test-cli-render-node.sh
```
