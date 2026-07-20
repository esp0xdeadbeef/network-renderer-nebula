# network-renderer-nebula

`network-renderer-nebula` emits Nebula runtime materialization from one
validated canonical network-realization bundle and, when required, one
normalized Nebula platform-binding bundle. It consumes no raw intent,
inventory, forwarding-model, or peer-renderer artifact as network authority.

It is a provider renderer, not a forwarding model.

Pipeline position: this repository is downstream of
`network-control-plane-model` and upstream of runtime consumers such as NixOS
or lab orchestration.

Migration, deviation, exception, transition, or temporary compatibility behavior
must be explicit in the README, tests, and owning layer before it is accepted.

```text
network-control-plane-model -> network-realization-model -> schema validation -> network-renderer-nebula
```

## Spec Chain

This renderer materializes Nebula runtime output from explicit CPM overlay data.
All behavior requirements originate from the FS-460 spec chain. Cross-cutting
renderer policy (CPM-only consumption, fail-closed, no naming inference) is
governed by FS-310.

### Owning Chain: Remote Egress over Nebula

| Layer | ID | Description |
|-------|----|-------------|
| URS   | §Overlays (L292–308), §Remote Egress (L211–213) | Provider overlay transport — explicit policy-routed path; readiness required before payload; underlay ≠ payload |
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

| URS § | Line(s) | Principle |
|-------|---------|-----------|
| Platform-Native Realization | L97 | Service generation belongs in the owning renderer or upstream model contract; host config stays thin |
| Intent/Realization Boundaries | L103–109 | Renderers do not create behavior outside modeled intent, inventory, and runtime facts |
| Determinism, Scope, Diagnostics | L125–135 | Deterministic output; missing/ambiguous facts fail at the owning layer; no heuristic repair |
| Least-Privilege Policy | L141–156 | Renderers materialize explicit platform-neutral policy; local defaults do not create allow rules |
| Overlay Transport | L192 | Endpoint identity, allowed peers, bootstrap, prefixes, payload classes, secret lifecycle, readiness, fail-closed |
| Reachability/Overlays | L303 | Overlay readiness required before overlay-dependent payload or policy-routed public egress |
| Reachability/Overlays | L308 | Underlay reachability does not become client, tenant, management, resolver, or payload reachability |
| Remote Egress over Nebula | L211–213 | Policy-routed remote egress over Nebula without DNS, route, source-prefix, underlay, management, tenant, or public-egress leaks |
| Cross-Layer Semantics | L225 | Remote-egress scenarios preserve source scope, tenant context, policy point, return-route, DNS policy, and leak-prevention across model layers |

### Cross-Cutting SMS (FS-310)

| Layer | ID | Description |
|-------|----|-------------|
| SMS   | FS-310-HDS-010-SDS-010-SMS-100 | Renderer CPM-only consumption — no raw intent/inventory reads |
| SMS   | FS-310-HDS-010-SDS-010-SMS-110 | Renderer fail-closed contract — throw on missing/ambiguous input |
| SMS   | FS-310-HDS-010-SDS-010-SMS-120 | Renderer no-naming-inference — never derive semantics from names |

### SMT Status (2026-06-13)

- FS-460-HDS-010-SDS-010-SMS-010 (Coordinator): **OK** — All child atoms tested at `network-renderer-nebula@b37f358`
- SMS-020 through SMS-050: **OK** — Full suite 29/29 passing
- FS-310 SMS-100: **OK** — CPM-only consumption enforced; no --inventory CLI, no raw inventory walks
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
  (URS L225: semantics preserved across model layers; URS L156: renderers materialize, don't create)
- CPM decides overlay ownership, termination, prefixes, policy, and public-exit
  semantics.
  (URS L156: renderers materialize explicit platform-neutral policy)
- This renderer consumes validated canonical output and emits Nebula runtime output.
  (URS L97: service gen belongs in owning renderer or upstream model contract)
- Missing, partial, or inconsistent CPM input must fail evaluation.
  (URS L131: missing facts fail at owning layer; URS L303: overlay readiness required before payload)
- Renderer output must be deterministic for the same CPM input.
  (URS L125: deterministic, scoped, traceable outputs)
- Consumers must wire the emitted output; they must not derive Nebula semantics
  locally.
  (URS L97: thin host config — renderer owns semantics, consumers import)

## Allowed

- Render Nebula runtime plans from CPM output.
  (URS L156: materialize explicit platform-neutral policy)
- Render node identities, overlay addresses, groups, lighthouse data, unsafe
  routes, service metadata, cert/signing inputs, and NixOS modules that enable
  Nebula itself.
  (URS L192: overlay transport — endpoint identity, allowed peers, bootstrap, prefixes, secret lifecycle)
- Render external lighthouse validation host material from explicit runtime
  values supplied before evaluation.
  (URS L125: scoped outputs; deterministic from supplied input)
- Emit Nebula-owned public-ingress runtime facts for the lighthouse service and
  compatible public services with concrete CPM provider endpoints. Public
  ingress for another provider class is reported as unsupported in the runtime
  facts and remains owned by that provider renderer.
  (URS L151: public ingress requires modeled source scope, destination, protocol, port, owning service)

## Not Allowed

These prohibitions implement URS L109 (renderers do not change behavior outside
modeled facts), URS L156 (local defaults do not create allow rules), and
URS L97 (thin host config).

- Read `intent.nix`, `inventory.nix`, `inventory-nixos.nix`, or forwarding-model
  files directly (FS-310 SMS-100).
- Decide forwarding policy, tenant reachability, overlay termination, public
  exit, DNS behavior, or prefix ownership.
  (URS L109, L156)
- Open host firewalls, install nftables policy, enable kernel forwarding, or
  otherwise make host/router reachability decisions for consumers.
  (URS L97, L109)
- Guess Nebula routes, addresses, lighthouses, or groups from names.
  (URS L131: no heuristic repair; URS L132: downstream does not repair missing upstream facts)
- Patch missing unsafe routes after boot.
  (URS L156: renderer-local defaults do not create behavior)
- Require `network-renderer-nixos` or `s-router-test` to reinterpret Nebula
  provider semantics.
  (URS L97: renderer owns its output semantics; consumers import, don't reinterpret)
- Materialize WireGuard, OpenVPN, or other non-Nebula provider public ingress
  through Nebula runtime facts.
  (URS L192: overlay transport models provider identity; URS L151: public ingress per owning provider)

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
