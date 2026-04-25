# network-renderer-nebula

`network-renderer-nebula` is the Nebula-specific runtime renderer for the
`network-*` pipeline.

It sits after the control-plane stage:

```text
intent.nix
  -> network-compiler
  -> network-forwarding-model
  -> network-control-plane-model
  -> network-renderer-nebula
```

## Scope

This renderer is responsible for Nebula runtime materialization only.

It consumes:

- control-plane overlay data from `network-control-plane-model`
- Nebula-specific realization data from inventory

It emits:

- per-overlay Nebula runtime plans
- per-node Nebula runtime plans
- node overlay addresses
- lighthouse metadata
- cert/signing inputs
- modeled unsafe routes
- runtime service/materialization metadata

It is **not** responsible for:

- overlay policy semantics
- `terminateOn`
- forwarding ownership
- public-exit policy
- tenant/public prefix ownership

Those belong upstream.

## Intended Consumer Model

The host or container runtime should not derive Nebula semantics locally.

The consumer should:

1. ask this renderer for the rendered node/runtime plan
2. mount the emitted profile/certs/config in the right place
3. start the emitted Nebula service

The consumer should **not**:

- invent overlay addresses
- compute route ownership
- decide who terminates an overlay
- patch missing unsafe routes after boot

## API

The flake exports:

- `libBySystem.<system>.renderer.buildNebulaPlan`
- `libBySystem.<system>.renderer.buildNebulaPlanFromPaths`

`buildNebulaPlan` takes an already-built control-plane model plus inventory.

`buildNebulaPlanFromPaths` compiles the control-plane model through the locked
chain first, then builds the Nebula runtime plan.

Both return a plan shaped like:

```nix
{
  overlays."<enterprise>::<site>::<overlay>" = {
    type = "nebula";
    name = "east-west";
    enterpriseName = "...";
    siteName = "...";
    overlayId = "...";
    ca = { name = "s-router-test-lab"; };
    lighthouse = { ... };
    nodes."<nodeName>" = { ... };
  };

  nodes."<nodeName>" = {
    overlayId = "...";
    overlayAddresses = [ "<ipv4-cidr>" "<ipv6-cidr>" ];
    groups = [ ... ];
    unsafeRoutes = [ ... ];
    service = { name = "nebula-runtime"; interface = "nebula1"; };
    materialization = { ... };
    lighthouse = { ... };
  };
}
```

## Security Model

This renderer does not own CA private-key storage.

Expected split:

- CA private key is encrypted at rest
- enrollment/signing happens on an explicit signer/enrollment box
- clients consume modeled node identities and signed certs
- clients do not self-assign Nebula identities

## Tests

The repo carries focused tests for:

- direct Nebula plan rendering from control-plane + inventory
- plan rendering from flake-locked example paths through the full upstream chain

Run:

```bash
bash tests/test-nebula-plan.sh
bash tests/test-nebula-plan-from-paths.sh
```
