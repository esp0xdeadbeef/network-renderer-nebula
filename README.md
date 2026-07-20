# network-renderer-nebula

`network-renderer-nebula` emits Nebula runtime materialization from one
validated canonical network-realization bundle and, when required, one
normalized Nebula platform-binding bundle. It consumes no raw intent,
inventory, forwarding-model, or peer-renderer artifact as network authority.

It is a provider renderer, not a forwarding model.

Pipeline position: this repository is downstream of canonical realization and
schema validation and upstream of runtime consumers such as NixOS or lab
orchestration.

Migration, deviation, exception, transition, or temporary compatibility behavior
must be explicit in the README, tests, and owning layer before it is accepted.

```text
network-control-plane-model -> network-realization-model -> schema validation -> network-renderer-nebula
```

## Spec Chain

This renderer materializes Nebula runtime output from validated canonical
overlay data. Provider behavior originates from the FS-460 chain;
cross-cutting canonical authority, fail-closed consumption, and coverage are
governed by FS-161, FS-162, FS-168, and FS-169.

### Owning Chain: Remote Egress over Nebula

| Layer | ID | Description |
|-------|----|-------------|
| URS   | Reachability, Routing, and Overlays; Canonical Realization and Renderer Boundary | Explicit provider-overlay path, readiness, underlay separation, and canonical renderer input |
| FS    | FS-460 | Remote Egress over Nebula — explicit policy-routed path with fail-closed |
| HDS   | FS-460-HDS-010 | Nebula Remote Egress hardware design — substrate facts (peer ID, overlay readiness, egress surface) |
| SDS   | FS-460-HDS-010-SDS-010 | Nebula Remote Egress software design — architecture, failure boundaries, overlay identity preservation |
| SMS   | FS-460-HDS-010-SDS-010-SMS-010 | **Coordinator** — Nebula renderer module: container binary in nix store, persistent daemon (not bash wrapper), service name `s88-provider-interface-nebula1.service` (SMT: OK) |
| SMS   | FS-460-HDS-010-SDS-010-SMS-020 | Underlay-payload separation — Nebula bootstrap reachability ≠ tenant/payload reachability |
| SMS   | FS-460-HDS-010-SDS-010-SMS-030 | Overlay route metadata — every overlay route record carries overlay identity + concrete peer-site identity |
| SMS   | FS-460-HDS-010-SDS-010-SMS-040 | Default route denial — WAN egress must not be converted to Nebula overlay reachability |
| SMS   | FS-460-HDS-010-SDS-010-SMS-050 | Delegated public-egress default — remote public-egress via overlay path only when explicitly modeled |

### URS Authority

Every renderer contract rule in this README traces to a URS requirement:

| URS category | Principle |
|--------------|-----------|
| Canonical Realization and Renderer Boundary | Every renderer consumes the same validated canonical bundle and optional bounded platform binding |
| Platform-Native Realization | Service generation belongs in the owning renderer; host configuration stays thin |
| Intent and Realization Boundaries | Renderers do not create behavior outside modeled authority and realization facts |
| Determinism, Scope, and Diagnostics | Deterministic output; missing or ambiguous facts fail at the owning layer; no heuristic repair |
| Reachability, Routing, and Overlays | Overlay readiness and underlay separation are required before payload or remote egress is valid |

### Cross-Cutting SMS (FS-310)

| Layer | ID | Description |
|-------|----|-------------|
| FS    | FS-161 / FS-162 | Canonical realization authority and peer-renderer boundary |
| FS    | FS-168 / FS-169 | Renderer consumption and rendered-output coverage |
| SMS   | FS-310-HDS-010-SDS-010-SMS-100 | Historical direct-CPM consumption guard — superseded as the positive renderer boundary |
| SMS   | FS-310-HDS-010-SDS-010-SMS-110 | Renderer fail-closed contract — throw on missing/ambiguous input |
| SMS   | FS-310-HDS-010-SDS-010-SMS-120 | Renderer no-naming-inference — never derive semantics from names |

### Historical SMT Status (2026-06-13)

- FS-460-HDS-010-SDS-010-SMS-010 (Coordinator): **OK** — All child atoms tested at `network-renderer-nebula@b37f358`
- SMS-020 through SMS-050: **OK** — Full suite 29/29 passing
- FS-310 SMS-100 proved the former CPM-only boundary. It does not by itself
  prove the current canonical renderer boundary or FS-168/FS-169 coverage.
- All child SMS rows delegate to coordinator. Coordinator has no independent construction beyond child module contracts.

### Pipeline

```
network-labs → compiler → NFM → CPM → realization → schema validation → Nebula renderer
```

The controlled API accepts one validated `bundle` and optional
`platformBinding`. The former direct `controlPlane` entry remains only for
superseded regression evidence. No separate inventory file, raw
`inventory.nix` parsing, or upstream source-file read is permitted.

### SMS-010 Key Requirements

- Container definition MUST include `nebula` binary in nix store closure
- Persistent systemd service required (no bash wrapper that exits)
- Service name: `s88-provider-interface-nebula1.service`

### Owning Repository

Construction tests: `network-renderer-nebula/tests/` (run via `bash run-all-tests.sh`)

## Contract

- Canonical network meaning is the renderer's sole semantic authority.
- Upstream CPM decides overlay ownership, termination, prefixes, policy, and
  public-exit semantics; `network-realization-model` preserves that meaning and
  provenance in the validated bundle.
- This renderer consumes validated canonical output and emits Nebula runtime output.
- Missing, partial, inconsistent, or unvalidated canonical input must fail.
- Renderer output must be deterministic for the same bundle and binding
  identities.
- Consumers must wire the emitted output; they must not derive Nebula semantics
  locally.

## Allowed

- Render Nebula runtime plans from the validated canonical bundle.
- Render node identities, overlay addresses, groups, lighthouse data, unsafe
  routes, service metadata, cert/signing inputs, and NixOS modules that enable
  Nebula itself.
- Render external lighthouse validation host material from explicit runtime
  values supplied before evaluation.
- Emit Nebula-owned public-ingress runtime facts for the lighthouse service and
  compatible public services with concrete canonical provider endpoints. Public
  ingress for another provider class is reported as unsupported in the runtime
  facts and remains owned by that provider renderer.

## Not Allowed

These prohibitions implement the URS canonical-renderer, no-invention, and thin
host-configuration boundaries.

- Read `intent.nix`, `inventory.nix`, `inventory-nixos.nix`, or forwarding-model
  files directly (FS-310 SMS-100).
- Consume raw CPM or another renderer's output as network-semantic authority.
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

**Controlled canonical rendering:**

- `renderer.canonical.hostModule` — bundle-only NixOS host integration
- `renderer.canonical.validateInput` — bundle, scope, target, and binding gate

**Retained internal and superseded direct rendering:**

- `buildNebulaPlan` — produce a Nebula runtime plan from CPM output
- `hostModule` — superseded direct-CPM NixOS regression entry
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

The flake also retains a CLI for standalone direct-CPM regression
materialization:

```bash
nix run github:esp0xdeadbeef/network-renderer-nebula -- \
  render-node --cpm ./cpm-bundle.json --node b-router-core-nebula
```

`--cpm` must point to JSON containing the historical CPM provider-neutral overlay output
(`controlPlane`/`control_plane_model` plus CPM-processed inventory). All data
reaches that legacy CLI through CPM output. The CLI is not current controlled
FS-166 evidence; no separate inventory file is accepted.

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
bash tests/test-FS-460-HDS-010-SDS-010-SMS-010-plan.sh
bash tests/test-FS-460-HDS-010-SDS-010-SMS-010-nebula-remote-egress-smt.sh
bash tests/test-FS-460-HDS-010-SDS-010-SMS-010-cli-render-node.sh
```
