{
  description = "network-renderer-nebula";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";
    network-control-plane-model.inputs.nixpkgs.follows = "nixpkgs";

    network-labs.url = "github:esp0xdeadbeef/network-labs";
  };

  outputs =
    { self
    , nixpkgs
    , network-control-plane-model
    , network-labs
    , ...
    }:
    let
      lib = nixpkgs.lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = lib.genAttrs systems;

      mkSystemLib =
        system:
        import ./s88/Enterprise/default.nix {
          inherit lib system;
          flakeInputs = {
            inherit
              nixpkgs
              network-control-plane-model
              network-labs
              ;
          };
        };

      withHostModule =
        systemLib:
        system:
        let
          cpmLib = network-control-plane-model.libBySystem.${system};
        in
        systemLib // {
          renderer = systemLib.renderer // {
            hostModule =
              { controlPlane
              , hostName
              , sopsProfileSecretPrefix ? "nebula-profile"
              , ...
              }:
              let
                # CPM output is the sole source of truth (SMS-100).
                # Renderers consume pre-compiled CPM; callers must provide
                # controlPlane already compiled from intent/inventory.
                cpmData = controlPlane.control_plane_model.data or { };

                # Check if this site has any nebula overlays before proceeding
                siteOverlays = lib.concatLists (
                  lib.mapAttrsToList
                    (_enterprise: enterpriseData:
                      lib.concatLists (
                        lib.mapAttrsToList
                          (_site: siteData:
                            let overlays = siteData.overlays or { };
                            in builtins.attrNames overlays
                          )
                          enterpriseData
                      )
                    )
                    cpmData
                );
                hasNebulaOverlay = builtins.any
                  (name: lib.hasPrefix "nebula" name || lib.hasPrefix "nebula-" name)
                  siteOverlays;
              in
              if !hasNebulaOverlay then
                { config, lib, pkgs, ... }: { }
              else
              let
                plan = systemLib.renderer.buildNebulaPlan {
                  inherit controlPlane;
                };
                hostedPlan = systemLib.renderer.selectHostedNebulaRuntimePlan {
                  nebulaRuntimePlan = plan;
                  inherit cpmData hostName;
                };
                containerNameForNode =
                  nodeName:
                  systemLib.renderer.runtimeContainerNameForHost {
                    inherit cpmData hostName;
                    logicalName = nodeName;
                  };
                profileDirFor = nodeName: "/persist/nebula-runtime/profiles/${nodeName}";
                profileSecretNamesFor = nodeName: [
                  "${sopsProfileSecretPrefix}-${nodeName}-ca-crt"
                  "${sopsProfileSecretPrefix}-${nodeName}-crt"
                  "${sopsProfileSecretPrefix}-${nodeName}-key"
                ];
              in
              { config, lib, pkgs, ... }:
              let
                nodeEntries =
                  lib.mapAttrsToList
                    (
                      nodeName: runtimeNode:
                      let
                        cName = containerNameForNode nodeName;
                        mod = systemLib.renderer.buildNebulaRuntimeNixosModule {
                          inherit pkgs nodeName runtimeNode;
                        };
                      in
                      {
                        container = cName;
                        module = mod;
                        profileDir = profileDirFor nodeName;
                        secretNames = profileSecretNamesFor nodeName;
                      }
                    )
                    (hostedPlan.nodes or { });

                groupedModules =
                  lib.foldl
                    (acc: entry: acc // {
                      ${entry.container} = (acc.${entry.container} or [ ]) ++ [ entry.module ];
                    })
                    { }
                    nodeEntries;

                groupedProfileDirs =
                  lib.foldl
                    (acc: entry: acc // {
                      ${entry.container} = (acc.${entry.container} or [ ]) ++ [ entry.profileDir ];
                    })
                    { }
                    nodeEntries;

                groupedSecretNames =
                  lib.foldl
                    (acc: entry: acc // {
                      ${entry.container} = (acc.${entry.container} or [ ]) ++ entry.secretNames;
                    })
                    { }
                    nodeEntries;

                profileDirs = lib.unique (map (entry: entry.profileDir) nodeEntries);

                bindMountsFor = dirs:
                  builtins.listToAttrs (
                    map
                      (profileDir: {
                        name = profileDir;
                        value = {
                          hostPath = profileDir;
                          isReadOnly = true;
                        };
                      })
                      (lib.unique dirs)
                  );
                secretBindMountsFor = secretNames:
                  builtins.listToAttrs (
                    map
                      (secretName: {
                        name = "/run/secrets/${secretName}";
                        value = {
                          hostPath = "/run/secrets/${secretName}";
                          isReadOnly = true;
                        };
                      })
                      (lib.unique secretNames)
                  );
                tunDeviceBindMounts = {
                  "/dev/net/tun" = {
                    hostPath = "/dev/net/tun";
                    isReadOnly = false;
                  };
                };
              in
              {
                systemd.tmpfiles.rules =
                  lib.optionals (profileDirs != [ ]) (
                    [
                      "d /persist/nebula-runtime 0700 root root -"
                      "d /persist/nebula-runtime/profiles 0700 root root -"
                    ]
                    ++ map (profileDir: "d ${profileDir} 0700 root root -") profileDirs
                  );

                containers = lib.mapAttrs
                  (containerName: modules: {
                    bindMounts =
                      (bindMountsFor (groupedProfileDirs.${containerName} or [ ]))
                      // (secretBindMountsFor (groupedSecretNames.${containerName} or [ ]))
                      // tunDeviceBindMounts;
                    allowedDevices = [
                      {
                        node = "/dev/net/tun";
                        modifier = "rw";
                      }
                    ];
                    additionalCapabilities = [
                      "CAP_NET_ADMIN"
                      "CAP_NET_RAW"
                    ];
                    config = lib.mkMerge modules;
                  })
                  groupedModules;
              };
          };
        };

      mkPackage = import ./s88/Enterprise/package.nix {
        inherit self nixpkgs;
      };
    in
    {
      libBySystem = forAllSystems (
        system:
        withHostModule (mkSystemLib system) system
      );

      lib = withHostModule (mkSystemLib "x86_64-linux") "x86_64-linux";

      packages = forAllSystems (system: {
        default = mkPackage system;
        network-renderer-nebula = mkPackage system;
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/network-renderer-nebula";
        };
      });
    };
}
