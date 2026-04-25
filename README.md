# network-renderer-nebula

Pipeline:

  - network-compiler normalizes intent
  - network-forwarding-model decides ownership, traversal, terminateOn, route intent
  - network-control-plane-model turns that into concrete overlay/control-plane data
  - nebula-renderer consumes only the Nebula slice of that data and emits runtime artifacts

  What the Nebula renderer should emit per actual Nebula node:

  - node identity
  - cert request/materialization inputs
  - nebula config.yml
  - lighthouse/peer endpoints
  - overlay addresses
  - unsafe routes
  - Nebula firewall derived from modeled overlay reachability
  - service/unit definitions

  What the host should do:

  - not understand Nebula semantics
  - not compute route policy
  - not decide who terminates overlays
  - only materialize the emitted node runtime in the right place
