{ lib
, pkgs
, nebulaRuntimePlan ? {
    overlays = { };
    nodes = { };
  }
, consumerName ? (throw "network-renderer-nebula: buildNebulaBootstrapExternalLighthouseModule requires consumerName (was hardcoded as \"s-router-test\")")
,
}:
let
  lighthouses = import ./external-lighthouse-module/lighthouses.nix { inherit lib nebulaRuntimePlan; };
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
      host = lh.listenHost;
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
        mtu = lh.mtu or (throw "network-renderer-nebula: external lighthouse ${lh.name} missing mtu from CPM");
        drop_multicast = false;
      };
    };
  };
in
{
  environment.etc."${consumerName}/external_lighthouse-nebula-lighthouses.json".text = builtins.toJSON lighthouses;

  systemd.tmpfiles.rules =
    [
      "d /persist/nebula-runtime 0700 root root -"
    ]
    ++ map
      (
        lh: "d /persist/nebula-runtime/profiles/${lh.certBaseName} 0700 root root -"
      )
      lighthouses;

  services.nebula.networks = builtins.listToAttrs (
    map
      (lh: {
        name = "lighthouse-${lh.name}";
        value = lighthouseNetworkFor lh;
      })
      lighthouses
  );
}
