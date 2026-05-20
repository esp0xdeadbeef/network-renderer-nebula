{ lib }:

{ nebulaRuntimePlan
, inventory
, hostName
,
}:
let
  realizationNodes = (((inventory.realization or { }).nodes or { }));
  selectedSiteKeys =
    lib.unique (
      lib.filter
        (key: key != "")
        (
          lib.mapAttrsToList
            (
              _nodeName: node:
                if (node.host or null) == hostName then
                  "${node.logicalNode.enterprise or ""}::${node.logicalNode.site or ""}"
                else
                  ""
            )
            realizationNodes
        )
    );
  isSelectedRuntimeNode =
    _nodeName: node:
    builtins.elem "${node.enterpriseName or ""}::${node.siteName or ""}" selectedSiteKeys;
in
nebulaRuntimePlan
  // {
  nodes = lib.filterAttrs isSelectedRuntimeNode (nebulaRuntimePlan.nodes or { });
  overlays =
    lib.filterAttrs
      (_overlayId: overlay: builtins.elem "${overlay.enterpriseName or ""}::${overlay.siteName or ""}" selectedSiteKeys)
      (nebulaRuntimePlan.overlays or { });
}
