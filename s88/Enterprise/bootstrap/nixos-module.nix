{ lib
, pkgs
, nebulaRuntimePlan ? {
    overlays = { };
    nodes = { };
  }
, externalLighthouseReturnIpv4Cidrs ? [ ]
, externalLighthousePublicIpv4SecretPath ? null
, externalLighthousePublicIpv6SecretPath ? null
, externalLighthouseSshHostSecretPath ? externalLighthousePublicIpv4SecretPath
, externalPortForwardPublicIpv4SecretPath ? externalLighthousePublicIpv4SecretPath
, externalPortForwardPublicIpv6SecretPath ? externalLighthousePublicIpv6SecretPath
, externalPortForwardNodeNames ? [ ]
, externalRuntimeNodeNames ? externalPortForwardNodeNames
, runtimeListenHosts ? { }
, externalRemoteLighthouseEndpoint4 ? null
, externalRemoteLighthouseEndpoint6 ? null
, externalRemoteLighthouseEndpoint4SecretPath ? null
, externalRemoteLighthouseEndpoint6SecretPath ? null
, externalSuppressPublicLighthouseStaticMap ? false
, sopsProfileSecretPrefix ? null
, profileSecretMaterializationMode ? null
,
}:
let
  plan = import ./nixos-module/plan.nix {
    inherit
      lib
      nebulaRuntimePlan
      externalLighthouseReturnIpv4Cidrs
      externalLighthousePublicIpv4SecretPath
      externalLighthousePublicIpv6SecretPath
      externalLighthouseSshHostSecretPath
      externalPortForwardPublicIpv4SecretPath
      externalPortForwardPublicIpv6SecretPath
      externalPortForwardNodeNames
      externalRuntimeNodeNames
      runtimeListenHosts
      externalRemoteLighthouseEndpoint4
      externalRemoteLighthouseEndpoint6
      externalRemoteLighthouseEndpoint4SecretPath
      externalRemoteLighthouseEndpoint6SecretPath
      externalSuppressPublicLighthouseStaticMap
      sopsProfileSecretPrefix
      ;
  };

  profileSecretEntries = lib.flatten (
    map
      (profileName:
        let
          names = plan.sopsProfileSecretNames.${profileName};
          paths = plan.sopsProfileSecretPaths.${profileName};
        in
        [
          {
            name = names.caCrt;
            path = paths.caCrt;
          }
          {
            name = names.cert;
            path = paths.cert;
          }
          {
            name = names.key;
            path = paths.key;
          }
        ]
      )
      plan.sopsProfileNames
  );
  mkRootSecret = entry: {
    owner = "root";
    mode = "0400";
    path = entry.path;
  };
  validProfileSecretMaterializationModes = [
    "operator-unlock"
    "sops-runtime"
  ];
  profileSecretMaterializationModeIsValid =
    builtins.elem profileSecretMaterializationMode validProfileSecretMaterializationModes;
  useSopsRuntimeProfileMaterialization = profileSecretMaterializationMode == "sops-runtime";
  materializeProfileSecret = entry: ''
    source_path="/run/secrets/${entry.name}"
    target_path=${lib.escapeShellArg entry.path}
    if [ ! -s "$source_path" ]; then
      echo "network-renderer-nebula: missing prepared Nebula profile secret $source_path for $target_path" >&2
      exit 1
    fi
    install -D -m 0400 -o root -g root "$source_path" "$target_path"
  '';
in
if plan.runtimeNodeNames == [ ] then
  { }
else
  {
    assertions = [
      {
        assertion = profileSecretMaterializationModeIsValid;
        message = "network-renderer-nebula: buildNebulaBootstrapNixosModule requires profileSecretMaterializationMode to be operator-unlock or sops-runtime";
      }
      {
        assertion = !useSopsRuntimeProfileMaterialization || sopsProfileSecretPrefix != null;
        message = "network-renderer-nebula: sops-runtime profile materialization requires sopsProfileSecretPrefix";
      }
    ];

    sops.secrets =
      if useSopsRuntimeProfileMaterialization then
        builtins.listToAttrs (
          map
            (entry: {
              inherit (entry) name;
              value = mkRootSecret entry;
            })
            profileSecretEntries
        )
      else
        { };

    environment.etc."s-router-test/nebula-bootstrap-spec.json".text =
      builtins.toJSON {
        runtimeNodes = plan.runtimeNodes;
        lighthouses = plan.lighthouses;
      };
    environment.etc."s-router-test/nebula-profile-targets.json".text =
      plan.sopsProfilePkiSecretPathsJson;

    systemd.tmpfiles.rules =
      [
        "d /persist/nebula-runtime 0700 root root -"
        "d /persist/nebula-runtime/profiles 0700 root root -"
      ]
      ++ map (profileName: "d /persist/nebula-runtime/profiles/${profileName} 0700 root root -") plan.sopsProfileNames;

    system.activationScripts =
      if useSopsRuntimeProfileMaterialization then
        {
          nebulaSopsProfiles = {
            deps = [ "setupSecrets" ];
            text = lib.concatStringsSep "\n" (map materializeProfileSecret profileSecretEntries);
          };
        }
      else
        { };
  }
