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
    let
      externalFingerprints =
        lib.filter
          (
            fingerprint:
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
            in
            !(builtins.hasAttr (base.lighthouse.node or "") (nebulaRuntimePlan.nodes or { }))
          )
          lighthouseFingerprints;
    in
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
      externalFingerprints;

  udpPorts = lib.unique (map (lh: lh.port) lighthouses);
  interfaces = lib.unique (map (lh: lh.interfaceName) lighthouses);
  stripPrefixLength = value: builtins.head (lib.splitString "/" value);
  lighthouseNetworkFor = lh: {
    enable = true;
    package = pkgs.nebula;
    ca = "/persist/nebula-runtime/profiles/${lh.certBaseName}/ca.crt";
    cert = "/persist/nebula-runtime/profiles/${lh.certBaseName}/${lh.certBaseName}.crt";
    key = "/persist/nebula-runtime/profiles/${lh.certBaseName}/${lh.certBaseName}.key";
    isLighthouse = true;
    lighthouses = [ ];
    listen = {
      host = "[::]";
      port = lh.port;
    };
    tun = {
      disable = true;
      device = lh.interfaceName;
    };
    firewall = {
      outbound = [
        {
          port = "any";
          proto = "any";
          host = "any";
        }
      ];
      inbound = [
        {
          port = "any";
          proto = "any";
          host = "any";
        }
      ];
    };
    settings = {
      static_map.network = "ip";
      static_host_map = { };
      lighthouse.am_lighthouse = true;
      tun = {
        disabled = true;
        dev = lh.interfaceName;
        mtu = 1200;
        drop_multicast = false;
      };
    };
  };
in
{
  environment.etc."s-router-test/external_lighthouse-nebula-lighthouses.json".text = builtins.toJSON lighthouses;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  networking.firewall.allowedUDPPorts = udpPorts;
  networking.firewall.trustedInterfaces = interfaces;

  systemd.tmpfiles.rules =
    [
      "d /persist/nebula-runtime 0700 root root -"
    ]
    ++ map (
      lh: "d /persist/nebula-runtime/profiles/${lh.certBaseName} 0700 root root -"
    ) lighthouses;

  services.nebula.networks = builtins.listToAttrs (
    map (lh: {
      name = "lighthouse-${lh.name}";
      value = lighthouseNetworkFor lh;
    }) lighthouses
  );
}
