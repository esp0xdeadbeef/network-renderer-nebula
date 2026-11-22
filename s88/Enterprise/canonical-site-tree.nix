# The producer's enterprise -> site tree, rebuilt from canonical content.
#
# WHY THIS EXISTS
# ---------------
# This renderer plans from `control_plane.data.<enterprise>.<site>`: the overlay
# topology, per-target runtime facts and the per-site tenant domains. Reaching
# for the model directly is exactly what RR_RAW_CPM_INPUT forbids, and
# the validated renderer input's control-plane envelope is the producer's CPM
# with a validation wrapper around it, not a canonical bundle.
#
# The producer already publishes those facts as canonical content:
#
#   canonicalSites.sites[]        { enterprise, site, facts }   <- facts is
#                                 `data.<enterprise>.<site>` verbatim
#   canonicalSites.overlays[]     { enterprise, site, overlay, ... facts }
#   canonicalRuntimeTargets.targets[]  { enterprise, site, target, facts, ... }
#
# So the tree is reconstructed from `facts` and nothing else. `facts` is the
# producer's own value, published rather than re-derived, so this projection is
# the identity on it: the renderer cannot disagree with the model because it is
# reading the model's own published value, reached through the canonical bundle.
#
# WHAT IT REFUSES TO DO
# ---------------------
# There is no fallback to the control-plane model. A bundle without canonical
# content is a bundle this renderer cannot plan from, and it says so. Inventing
# a fallback would restore the very dependency this module removes, and the
# failure would reappear only on the site that lacked the field.
{ lib }:

{ canonical, expected }:
let
  sites = (canonical.canonicalSites or { }).sites or [ ];

  place = tree: entry:
    tree
    // {
      ${entry.enterprise} =
        (tree.${entry.enterprise} or { })
        // {
          ${entry.site} = entry.facts;
        };
    };
  tree = builtins.foldl' place { } sites;
in
# A site that reaches the plan has an overlay to render, so an empty tree is a
# bundle that carries no canonical site records. Fail closed and say why:
# silently returning no plan is the "silent fail-open" FS-460 names (an s88
# overlay unit waiting forever for a link no daemon creates).
builtins.deepSeq
  (
    if tree == { } then
      throw "network-renderer-nebula: ${expected} was asked to plan, but the bundle carries no canonical site records"
    else
      true
  )
  tree
