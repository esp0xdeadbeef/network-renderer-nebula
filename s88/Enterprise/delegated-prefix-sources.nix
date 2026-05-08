{
  lib,
  helpers,
  cpmData,
}:

let
  inherit (helpers) sortedAttrNames;

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];
  isString = value: builtins.isString value && value != "";

  sourceFileForAdvertisement =
    target: adv:
    let
      targetExternalValidation = attrsOrEmpty (target.externalValidation or null);
      advExternalValidation = attrsOrEmpty (adv.externalValidation or null);
      delegatedPrefix = attrsOrEmpty (adv.delegatedPrefix or null);
    in
    if isString (delegatedPrefix.sourceFile or null) then
      delegatedPrefix.sourceFile
    else if isString (advExternalValidation.delegatedPrefixSecretPath or null) then
      advExternalValidation.delegatedPrefixSecretPath
    else if isString (targetExternalValidation.delegatedPrefixSecretPath or null) then
      targetExternalValidation.delegatedPrefixSecretPath
    else
      null;

  entriesForTarget =
    target:
    let
      advertisements = attrsOrEmpty (target.advertisements or null);
      ipv6Ra = listOrEmpty (advertisements.ipv6Ra or null);
    in
    builtins.concatMap (
      adv:
      let
        routerInterface = attrsOrEmpty (adv.routerInterface or null);
        subnet = routerInterface.subnet6 or null;
        sourceFile = sourceFileForAdvertisement target adv;
      in
      if isString subnet && isString sourceFile then
        [ { name = subnet; value = sourceFile; } ]
      else
        [ ]
    ) (lib.filter builtins.isAttrs ipv6Ra);

  runtimeTargetsForSite = site: attrsOrEmpty (site.runtimeTargets or null);

  entries =
    builtins.concatLists (
      builtins.concatLists (
        map (
          enterpriseName:
          let
            sites = attrsOrEmpty cpmData.${enterpriseName};
          in
          map (
            siteName:
            let
              runtimeTargets = runtimeTargetsForSite sites.${siteName};
            in
            builtins.concatMap (targetName: entriesForTarget runtimeTargets.${targetName}) (
              sortedAttrNames runtimeTargets
            )
          ) (sortedAttrNames sites)
        ) (sortedAttrNames cpmData)
      )
    );
in
builtins.listToAttrs entries
