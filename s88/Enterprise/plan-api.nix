{ lib, helpers }:

{ controlPlane
, caName ? "nebula-ca"
,
}:

let
  cpm =
    if controlPlane ? control_plane_model && builtins.isAttrs controlPlane.control_plane_model then
      controlPlane.control_plane_model
    else
      throw "network-renderer-nebula: controlPlane.control_plane_model is required";

  cpmData = cpm.data or { };

  entries = import ./overlay-entries.nix {
    inherit lib helpers cpmData;
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
