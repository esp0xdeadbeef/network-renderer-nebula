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
        (key: key != null)
        (
          lib.mapAttrsToList
            (
              _nodeName: node:
                if (node.host or null) == hostName then
                  let
                    ent = node.logicalNode.enterprise or null;
                    site = node.logicalNode.site or null;
                  in
                    if builtins.isString ent && builtins.isString site
                    then "${ent}::${site}"
                    else null
                else
                  null
            )
            realizationNodes
        )
    );
  isSelectedRuntimeNode =
    _nodeName: node:
    builtins.elem "${node.enterpriseName or null}::${node.siteName or null}" selectedSiteKeys;
in
nebulaRuntimePlan
  // {
  nodes = lib.filterAttrs isSelectedRuntimeNode (nebulaRuntimePlan.nodes or { });
  overlays =
    lib.filterAttrs
      (_overlayId: overlay: builtins.elem "${overlay.enterpriseName or null}::${overlay.siteName or null}" selectedSiteKeys)
      (nebulaRuntimePlan.overlays or { });
}
