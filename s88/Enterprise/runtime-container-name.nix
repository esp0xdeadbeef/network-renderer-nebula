{ lib }:

{ cpmData
, hostName
, logicalName
,
}:

let
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  # Find runtimeTarget across all sites where logicalNode.name matches and placement.host matches
  findTarget =
    let
      allTargets =
        lib.concatLists (
          lib.mapAttrsToList
            (_enterpriseName: enterpriseSites:
              lib.concatLists (
                lib.mapAttrsToList
                  (_siteName: siteData:
                    builtins.attrValues (attrsOrEmpty (siteData.runtimeTargets or null))
                  )
                  (attrsOrEmpty enterpriseSites)
              )
            )
            (attrsOrEmpty cpmData)
        );
      matches =
        lib.filter
          (target:
            ((target.logicalNode or { }).name or null) == logicalName
            && ((target.placement or { }).host or null) == hostName
          )
          allTargets;
    in
    if matches == [ ] then null else builtins.head matches;

  target = findTarget;

  # Use container runtime name from CPM, fallback to logicalName
  containerName =
    let
      containers = if target != null then target.containers or [ ] else [ ];
      firstContainer = if containers != [ ] then builtins.head containers else null;
    in
    if firstContainer != null && builtins.isString (firstContainer.container or null) then
      firstContainer.container
    else
      logicalName;
in
if target == null then
  throw "network-renderer-nebula: missing ${logicalName} runtime target on ${hostName}"
else
  containerName
