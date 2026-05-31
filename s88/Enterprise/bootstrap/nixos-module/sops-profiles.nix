{ lib
, lighthouses
, runtimeNodeNames
, sopsProfileSecretPrefix
,
}:

let
  externalLighthouseCertBaseNames =
    map (lighthouse: lighthouse.certBaseName) (
      lib.filter (lighthouse: lighthouse.internal != true) (builtins.attrValues lighthouses)
    );
  profileNames = lib.unique (runtimeNodeNames ++ externalLighthouseCertBaseNames);
  secretNamesFor = profileName:
    let
      baseName = "${sopsProfileSecretPrefix}-${profileName}";
    in
    {
      caCrt = "${baseName}-ca-crt";
      cert = "${baseName}-crt";
      key = "${baseName}-key";
    };
  secretNames =
    if sopsProfileSecretPrefix == null then
      { }
    else
      builtins.listToAttrs (
        map
          (profileName: {
            name = profileName;
            value = secretNamesFor profileName;
          })
          profileNames
      );
  secretPaths =
    builtins.listToAttrs (
      map
        (profileName: {
          name = profileName;
          value = {
            caCrt = "/persist/nebula-runtime/profiles/${profileName}/ca.crt";
            cert = "/persist/nebula-runtime/profiles/${profileName}/${profileName}.crt";
            key = "/persist/nebula-runtime/profiles/${profileName}/${profileName}.key";
          };
        })
        profileNames
    );
in
{
  inherit profileNames secretNames secretPaths;
  pkiSecretPathsJson = builtins.toJSON secretPaths;
}
