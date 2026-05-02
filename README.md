# network-renderer-nebula

`network-renderer-nebula` emits Nebula runtime materialization from explicit
CPM overlay data and Nebula realization input.

It is a provider renderer, not a forwarding model.

```text
network-forwarding-model -> network-control-plane-model -> network-renderer-nebula
```

## Contract

- The forwarding model and CPM are the source of truth.
- CPM decides overlay ownership, termination, prefixes, policy, and public-exit
  semantics.
- This renderer consumes explicit Nebula input and emits Nebula runtime output.
- Missing, partial, or inconsistent Nebula input must fail evaluation.
- Consumers must wire the emitted output; they must not derive Nebula semantics
  locally.

## Allowed

- Render Nebula runtime plans.
- Render node identities, overlay addresses, groups, lighthouse data, unsafe
  routes, service metadata, cert/signing inputs, and NixOS bootstrap modules.
- Render external lighthouse validation host material from explicit runtime
  values supplied before evaluation.

## Not Allowed

- Decide forwarding policy, tenant reachability, overlay termination, public
  exit, DNS behavior, or prefix ownership.
- Guess Nebula routes, addresses, lighthouses, or groups from names.
- Patch missing unsafe routes after boot.
- Require `network-renderer-nixos` or `s-router-test` to reinterpret Nebula
  provider semantics.

## API

The flake exports:

- `libBySystem.<system>.renderer.buildNebulaPlan`
- `libBySystem.<system>.renderer.buildNebulaPlanFromPaths`
- `libBySystem.<system>.renderer.buildNebulaBootstrapNixosModule`
- `libBySystem.<system>.renderer.buildExternalLighthouseNixosModule`

## Tests

Run:

```bash
bash tests/test-nebula-plan.sh
bash tests/test-nebula-plan-from-paths.sh
bash tests/test-nebula-bootstrap-module.sh
```
