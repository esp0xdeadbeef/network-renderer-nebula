{
  lib,
  network-realization-model,
}:
systemLib: _system:
systemLib
// {
  renderer = systemLib.renderer // rec {
    hostModule =
      {
        controlPlane,
        hostName,
        sopsProfileSecretPrefix ? "nebula-profile",
        ...
      }:
      let
        cpmData = controlPlane.control_plane_model.data or { };
        overlayValues = lib.concatLists (
          lib.mapAttrsToList (
            _enterprise: enterpriseData:
            lib.concatLists (
              lib.mapAttrsToList (_site: siteData: builtins.attrValues (siteData.overlays or { })) enterpriseData
            )
          ) cpmData
        );
        # Gate on the modeled provider, not the overlay name: an overlay whose
        # provider is "nebula" must be realized regardless of what it is called
        # (e.g. "garnet"). Name-prefix matching silently skipped such overlays.
        hasNebulaOverlay = builtins.any (
          overlay: (overlay.provider or null) == "nebula"
        ) overlayValues;
      in
      if !hasNebulaOverlay then
        {
          config,
          lib,
          pkgs,
          ...
        }:
        { }
      else
        let
          plan = systemLib.renderer.buildNebulaPlan { inherit controlPlane; };
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
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          nodeEntries = lib.mapAttrsToList (
            nodeName: runtimeNode:
            let
              container = containerNameForNode nodeName;
            in
            {
              inherit container nodeName;
              module = systemLib.renderer.buildNebulaRuntimeNixosModule {
                inherit pkgs nodeName runtimeNode;
              };
              profileDir = profileDirFor nodeName;
              secretNames = profileSecretNamesFor nodeName;
            }
          ) (hostedPlan.nodes or { });

          groupByContainer =
            selector:
            lib.foldl (
              acc: entry:
              acc
              // {
                ${entry.container} = (acc.${entry.container} or [ ]) ++ selector entry;
              }
            ) { } nodeEntries;

          groupedModules = groupByContainer (entry: [ entry.module ]);
          groupedProfileDirs = groupByContainer (entry: [ entry.profileDir ]);
          groupedSecretNames = groupByContainer (entry: entry.secretNames);
          profileDirs = lib.unique (map (entry: entry.profileDir) nodeEntries);

          mkBindMounts =
            readOnly: paths:
            builtins.listToAttrs (
              map (path: {
                name = path;
                value = {
                  hostPath = path;
                  isReadOnly = readOnly;
                };
              }) (lib.unique paths)
            );
        in
        {
          systemd.tmpfiles.rules = lib.optionals (profileDirs != [ ]) (
            [
              "d /persist/nebula-runtime 0700 root root -"
              "d /persist/nebula-runtime/profiles 0700 root root -"
            ]
            ++ map (profileDir: "d ${profileDir} 0700 root root -") profileDirs
          );

          # FS-460-HDS-010-SDS-010-SMS-010: the container reads its PKI from
          # /persist/nebula-runtime/profiles/<node>/{ca.crt,<node>.crt,<node>.key}.
          # Populate each node profile dir from its SOPS-backed secrets
          # (nebula-profile-<node>-{ca-crt,crt,key}) before the container starts.
          systemd.services = builtins.listToAttrs (
            map
              (nodeName:
                let
                  dir = profileDirFor nodeName;
                  secrets = profileSecretNamesFor nodeName;
                in
                {
                  name = "nebula-profile-${nodeName}";
                  value = {
                    description = "Materialize the Nebula PKI profile for ${nodeName}";
                    wantedBy = [ "multi-user.target" ];
                    before = [ "container@${containerNameForNode nodeName}.service" ];
                    # SOPS secrets are materialized by the boot activation
                    # script, not a sops-nix.service unit on every host, so do
                    # not depend on a named unit; the secrets are present by
                    # multi-user.target.
                    serviceConfig.Type = "oneshot";
                    serviceConfig.RemainAfterExit = true;
                    script = ''
                      set -euo pipefail
                      install -d -m 0700 ${dir}
                      install -m 0400 /run/secrets/${builtins.elemAt secrets 0} ${dir}/ca.crt
                      install -m 0400 /run/secrets/${builtins.elemAt secrets 1} ${dir}/${nodeName}.crt
                      install -m 0400 /run/secrets/${builtins.elemAt secrets 2} ${dir}/${nodeName}.key
                    '';
                  };
                })
              (map (e: e.nodeName) nodeEntries)
          );

          containers = lib.mapAttrs (containerName: modules: {
            bindMounts =
              (mkBindMounts true (groupedProfileDirs.${containerName} or [ ]))
              // (mkBindMounts true (
                map (name: "/run/secrets/${name}") (groupedSecretNames.${containerName} or [ ])
              ))
              // {
                "/dev/net/tun" = {
                  hostPath = "/dev/net/tun";
                  isReadOnly = false;
                };
              };
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
          }) groupedModules;
        };

    canonical = {
      validateInput =
        {
          bundle,
          platformBinding ? null,
        }:
        network-realization-model.lib.validateRendererInput {
          inherit bundle platformBinding;
          expectedTarget = "nebula";
        };
      hostModule =
        {
          bundle,
          platformBinding ? null,
          ...
        }@rendererInput:
        let
          validated = canonical.validateInput { inherit bundle platformBinding; };
          forwarded = builtins.removeAttrs rendererInput [
            "bundle"
            "platformBinding"
          ];
        in
        hostModule (
          forwarded
          // {
            controlPlane = validated.controlPlaneEnvelope;
            canonicalBundleIdentity = validated.bundleIdentity;
            canonicalBindingIdentity = validated.bindingIdentity;
          }
        );
    };
  };
}
