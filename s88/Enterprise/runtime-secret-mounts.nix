{ lib }:

{ containers
, runtimeSecretsDir
, secretNames
,
}:
let
  secretMounts =
    lib.genAttrs
      (builtins.map (secretName: "/run/secrets/${secretName}") secretNames)
      (secretPath: {
        hostPath = secretPath;
        isReadOnly = true;
      });
in
{
  inherit secretNames;
  tmpfilesRules =
    builtins.map
      (secretName: "L+ /run/secrets/${secretName} - - - - ${runtimeSecretsDir}/${secretName}")
      secretNames;
  containers =
    lib.mapAttrs
      (_containerName: container:
        container
        // {
          bindMounts =
            (if builtins.isAttrs (container.bindMounts or null) then container.bindMounts else { })
            // secretMounts;
        })
      containers;
}
