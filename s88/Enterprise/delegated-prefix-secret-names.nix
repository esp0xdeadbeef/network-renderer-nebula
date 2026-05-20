{ lib }:

{ controlPlanes }:
let
  controlPlaneDataList =
    builtins.map
      (
        controlPlane:
        let
          controlPlaneModel = controlPlane.control_plane_model or { };
        in
        if builtins.isAttrs (controlPlaneModel.data or null) then
          controlPlaneModel.data
        else
          controlPlane.data or { }
      )
      controlPlanes;

  runtimeTargets =
    lib.foldl'
      (
        targetAcc: controlPlaneData:
          targetAcc
          // lib.foldlAttrs
            (
              enterpriseAcc: _enterpriseName: enterpriseSites:
                enterpriseAcc
                // lib.foldlAttrs
                  (
                    siteAcc: _siteName: siteData:
                      siteAcc // (siteData.runtimeTargets or { })
                  )
                  { }
                  enterpriseSites
            )
            { }
            controlPlaneData
      )
      { }
      controlPlaneDataList;

  secretNameFromPath =
    path:
    if builtins.isString path && lib.hasPrefix "/run/secrets/" path then
      lib.removePrefix "/run/secrets/" path
    else
      "";

  routedPrefixSecretNamesForTarget =
    target:
    lib.concatMap
      (
        advertisement:
        let
          delegatedPrefix =
            if builtins.isAttrs (advertisement.delegatedPrefix or null) then
              advertisement.delegatedPrefix
            else
              { };
        in
        [ (secretNameFromPath (delegatedPrefix.sourceFile or "")) ]
      )
      ((target.advertisements or { }).ipv6Ra or [ ]);
in
lib.sort builtins.lessThan (
  lib.unique (
    lib.filter
      (name: builtins.isString name && name != "")
      (
        lib.mapAttrsToList
          (_targetName: target: (target.externalValidation or { }).delegatedPrefixSecretName or "")
          runtimeTargets
        ++ lib.concatLists (lib.mapAttrsToList (_targetName: routedPrefixSecretNamesForTarget) runtimeTargets)
      )
  )
)
