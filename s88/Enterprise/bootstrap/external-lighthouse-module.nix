{
  lib,
  pkgs,
  nebulaRuntimePlan ? {
    overlays = { };
    nodes = { };
  },
}:
let
  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizeName =
    value:
    lib.replaceStrings
      [
        "::"
        ":"
        "."
        "/"
        " "
      ]
      [
        "-"
        "-"
        "-"
        "-"
        "-"
      ]
      value;

  overlayNames = sortedAttrNames (nebulaRuntimePlan.overlays or { });
  toPort = value: builtins.fromJSON (builtins.toString value);
  lighthouseFingerprints =
    lib.unique (
      map
        (
          overlayId:
          let
            overlay = nebulaRuntimePlan.overlays.${overlayId};
            lighthouse = overlay.lighthouse or { };
            addresses = lighthouse.overlayAddresses or [ ];
          in
          lib.concatStringsSep "|" [
            (builtins.elemAt addresses 0)
            (builtins.elemAt addresses 1)
            (lighthouse.endpoint or "")
            (lighthouse.endpoint6 or "")
            (builtins.toString (lighthouse.port or 4242))
          ]
        )
        overlayNames
    );

  lighthouses =
    lib.imap0
      (
        index: fingerprint:
        let
          matching =
            lib.filter
              (
                overlayId:
                let
                  overlay = nebulaRuntimePlan.overlays.${overlayId};
                  lighthouse = overlay.lighthouse or { };
                  addresses = lighthouse.overlayAddresses or [ ];
                in
                fingerprint
                == lib.concatStringsSep "|" [
                  (builtins.elemAt addresses 0)
                  (builtins.elemAt addresses 1)
                  (lighthouse.endpoint or "")
                  (lighthouse.endpoint6 or "")
                  (builtins.toString (lighthouse.port or 4242))
                ]
              )
              overlayNames;
          base = nebulaRuntimePlan.overlays.${builtins.head matching};
          logicalName = sanitizeName base.name;
          certBaseName = "${logicalName}-${base.lighthouse.node or "lighthouse"}";
        in
        {
          name = logicalName;
          inherit certBaseName;
          serviceName = "nebula-s-router-test-lighthouse-${logicalName}";
          interfaceName = "nebula${builtins.toString index}";
          port = toPort (base.lighthouse.port or 4242);
          overlayNetwork4 = builtins.elemAt base.lighthouse.overlayAddresses 0;
          overlayNetwork6 = builtins.elemAt base.lighthouse.overlayAddresses 1;
        }
      )
      lighthouseFingerprints;

  udpPorts = lib.unique (map (lh: lh.port) lighthouses);
  interfaces = lib.unique (map (lh: lh.interfaceName) lighthouses);
in
{
  environment.etc."s-router-test/external_lighthouse-nebula-lighthouses.json".text = builtins.toJSON lighthouses;

  environment.systemPackages = [ pkgs.nebula ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  networking.firewall.allowedUDPPorts = udpPorts;
  networking.firewall.trustedInterfaces = interfaces;

  systemd.tmpfiles.rules =
    [
      "d /persist/nebula-runtime 0700 root root -"
      "d /persist/nebula-runtime/lighthouses 0700 root root -"
    ]
    ++ map (
      lh: "d /persist/nebula-runtime/lighthouses/${lh.certBaseName} 0700 root root -"
    ) lighthouses;

  systemd.services =
    builtins.listToAttrs (
      map
        (lh: {
          name = lh.serviceName;
          value = {
            description = "Nebula lighthouse for s-router-test validation (${lh.name})";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            unitConfig.ConditionPathExists =
              "/persist/nebula-runtime/lighthouses/${lh.certBaseName}/${lh.certBaseName}.config.yml";
            serviceConfig = {
              ExecStart =
                "${pkgs.nebula}/bin/nebula -config /persist/nebula-runtime/lighthouses/${lh.certBaseName}/${lh.certBaseName}.config.yml";
              Restart = "always";
              RestartSec = 2;
            };
          };
        })
        lighthouses
    );
}
