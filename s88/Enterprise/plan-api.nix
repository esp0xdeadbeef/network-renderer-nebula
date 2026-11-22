{ lib, helpers }:

{ controlPlane
, caName ? "nebula-ca"
# The canonical site section from the validated bundle. Production passes this;
# it is the only source of network content the plan maps.
, canonicalContent ? { }
# A caller that already holds the enterprise -> site tree (a test constructing
# its own input, or a caller holding published site facts) may pass it directly
# instead. This is the same tree `canonicalContent` yields, so neither form is a
# different source of meaning -- and neither is the control-plane model.
, cpmData ? null
,
}:

let
  # The enterprise -> site tree comes from the bundle's canonical site records,
  # not from the control-plane envelope's model field. Reading it here is what
  # RR_RAW_CPM_INPUT forbids, and `controlPlane` is that model with a validation
  # wrapper around it. See ./canonical-site-tree.nix.
  #
  # `controlPlane` stays in the signature because the plan's provenance and the
  # renderer's other entry points share it; it is not read for site topology.
  siteTree =
    if cpmData != null then
      cpmData
    else
      import ./canonical-site-tree.nix { inherit lib; } {
        canonical = canonicalContent;
        expected = "nebula overlay plan";
      };

  entries = import ./overlay-entries.nix {
    inherit lib helpers;
    cpmData = siteTree;
  };

  rawOverlays = builtins.listToAttrs (
    map
      (
        entry:
        import ./overlay-plan.nix {
          inherit
            lib
            helpers
            caName
            entry
            ;
        }
      )
      entries
  );

  rawNodeEntries = builtins.concatLists (
    map
      (
        overlayId:
        map
          (nodeName: {
            name = nodeName;
            value = rawOverlays.${overlayId}.nodes.${nodeName};
          })
          (helpers.sortedAttrNames rawOverlays.${overlayId}.nodes)
      )
      (helpers.sortedAttrNames rawOverlays)
  );

  rawNodes =
    (import ./node-merge.nix { inherit lib helpers; }).mergeRawNodeEntries rawNodeEntries;

  inherit
    (import ./relay-resolution.nix {
      inherit helpers rawNodes;
    })
    relayForNode
    ;
  relayStaticHostMap = import ./relay-static-host-map.nix { inherit lib helpers; };

  baseNodes =
    builtins.mapAttrs
      (
        nodeName: node:
          node
          // {
            relay = relayForNode nodeName node;
          }
      )
      rawNodes;

  nodes = builtins.mapAttrs (_: relayStaticHostMap.addToNode baseNodes) baseNodes;

  overlays =
    builtins.mapAttrs
      (
        overlayId: overlay:
          overlay
          // {
            nodes = builtins.mapAttrs (nodeName: _: nodes.${nodeName}) overlay.nodes;
          }
      )
      rawOverlays;
in
{ inherit overlays nodes; }
