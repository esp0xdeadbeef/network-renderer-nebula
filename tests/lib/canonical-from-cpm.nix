# Derive a bundle's canonical content from a control-plane artifact.
#
# TESTS ONLY. `tests/` is excluded from the RR_RAW_CPM_INPUT scan on purpose: a
# test may build a CPM as INPUT, and this is where that is allowed. The
# renderer's implementation must not do this -- it receives the canonical
# section from network-realization-model's `validateRendererInput`.
#
# Each caller here constructs a CPM (or mutates one) and hands it to a renderer
# API. The renderer API takes canonical content, so the CPM has to be realized
# first, exactly as production does. Mutations therefore have to be applied to
# `canonicalSites` as well as to the model -- which is the correct place to
# mutate: canonical content is what the renderer maps.
{ repoRoot, system ? "x86_64-linux" }:
let
  flake = builtins.getFlake ("path:" + repoRoot);
in
{
  # The canonical section a caller should hand to a renderer API.
  canonicalFromCpm =
    cpm:
    flake.inputs.network-realization-model.lib.canonicalFor cpm.control_plane_model;

  # The canonical site section alone, for the APIs that take `canonicalSites`.
  canonicalSitesFromCpm = cpm: (canonicalFromCpm cpm).canonicalSites;
}
