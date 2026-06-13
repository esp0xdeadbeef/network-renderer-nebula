{ lib }:

{ nebulaRuntimePlan
, cpmData
, hostName
,
}:

let
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  # Collect all runtimeTargets from CPM data and find which enterprise::site pairs
  # have targets placed on this host
  selectedSiteKeys =
    lib.unique (
      lib.filter
        (key: key != null)
        (
          lib.concatLists (
            lib.mapAttrsToList
              (enterpriseName: enterpriseSites:
                lib.concatLists (
                  lib.mapAttrsToList
                    (siteName: siteData:
                      let
                        targets = attrsOrEmpty (siteData.runtimeTargets or null);
                      in
                      lib.mapAttrsToList
                        (_targetName: target:
                          if ((target.placement or { }).host or null) == hostName then
                            "${enterpriseName}::${siteName}"
                          else
                            null
                        )
                        targets
                    )
                    (attrsOrEmpty enterpriseSites)
                )
              )
              (attrsOrEmpty cpmData)
          )
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
