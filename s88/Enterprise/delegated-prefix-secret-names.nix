{ lib }:

{
  # The enterprise -> site tree, as published by the bundle's canonical site
  # records. Either form is accepted so a caller holding canonical content
  # (`canonicalSites`) and a caller holding the tree itself (`cpmData`) both
  # work; neither is the control-plane model, which this renderer must not read.
  canonicalSites ? null,
  cpmData ? null,
}:
let
  controlPlaneDataList = [
    (if cpmData != null then
      cpmData
    else
      import ./canonical-site-tree.nix { inherit lib; } {
        canonical = canonicalSites;
        expected = "delegated-prefix secret names";
      })
  ];

  runtimeTargets = lib.foldl' (
    targetAcc: controlPlaneData:
    targetAcc
    // lib.foldlAttrs (
      enterpriseAcc: _enterpriseName: enterpriseSites:
      enterpriseAcc
      // lib.foldlAttrs (
        siteAcc: _siteName: siteData:
        siteAcc // (siteData.runtimeTargets or { })
      ) { } enterpriseSites
    ) { } controlPlaneData
  ) { } controlPlaneDataList;

  secretNameFromPath =
    path:
    if builtins.isString path && lib.hasPrefix "/run/secrets/" path then
      lib.removePrefix "/run/secrets/" path
    else
      "";

  routedPrefixSecretNamesForTarget =
    target:
    lib.concatMap (
      advertisement:
      let
        delegatedPrefix =
          if builtins.isAttrs (advertisement.delegatedPrefix or null) then
            advertisement.delegatedPrefix
          else
            { };
      in
      [ (secretNameFromPath (delegatedPrefix.sourceFile or null)) ]
    ) ((target.advertisements or { }).ipv6Ra or [ ]);
in
lib.sort builtins.lessThan (
  lib.unique (
    lib.filter (name: builtins.isString name && name != "") (
      lib.concatLists (lib.mapAttrsToList (_targetName: routedPrefixSecretNamesForTarget) runtimeTargets)
    )
  )
)
