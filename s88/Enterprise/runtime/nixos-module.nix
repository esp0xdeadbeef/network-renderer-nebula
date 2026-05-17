{
  lib,
  pkgs,
  nodeName,
  runtimeNode,
}:

let
  networkName = "runtime";
  interfaceName = runtimeNode.service.interface or "nebula1";
  pkiBase = "/persist/nebula-runtime/profiles/${nodeName}";
  isLighthouse = (runtimeNode.lighthouse.node or null) == nodeName;
  lighthouseIps = runtimeNode.lighthouse.overlayIps or [ ];
  lighthouseIp4 = builtins.elemAt lighthouseIps 0;
  lighthouseIp6 = builtins.elemAt lighthouseIps 1;
  lighthouseEndpoints = runtimeNode.lighthouse.endpoints or [ ];
  renderedNetwork = runtimeNode.nebulaNetwork or {
    settings = { };
  };
  staticHostMap =
    if isLighthouse then
      { }
    else
      {
        ${lighthouseIp4} = lighthouseEndpoints;
        ${lighthouseIp6} = lighthouseEndpoints;
      };
  relay = runtimeNode.relay or { };
  listenHost = runtimeNode.service.listenHost or "[::]";
  listenPort = lib.toInt (runtimeNode.lighthouse.port or 4242);
in
{
  systemd.tmpfiles.rules = [
    "d /persist/nebula-runtime 0700 root root -"
    "d /persist/nebula-runtime/profiles 0700 root root -"
    "d ${pkiBase} 0700 root root -"
  ];

  networking.firewall.extraInputRules = ''
    iifname "nebula1" accept comment "s88-nebula-runtime-input"
  '';
  networking.firewall.extraForwardRules = ''
    iifname "nebula1" accept comment "s88-nebula-runtime-forward-in"
    oifname "nebula1" accept comment "s88-nebula-runtime-forward-out"
  '';
  networking.nftables.ruleset = lib.mkAfter ''
    insert rule inet router input iifname "nebula1" accept comment "s88-nebula-runtime-input"
    insert rule inet router forward iifname "nebula1" accept comment "s88-nebula-runtime-forward-in"
    insert rule inet router forward oifname "nebula1" accept comment "s88-nebula-runtime-forward-out"
  '';

  services.nebula.networks.${networkName} = {
    enable = true;
    package = pkgs.nebula;
    ca = "${pkiBase}/ca.crt";
    cert = "${pkiBase}/${nodeName}.crt";
    key = "${pkiBase}/${nodeName}.key";
    staticHostMap = staticHostMap;
    isLighthouse = isLighthouse;
    isRelay = relay.amRelay or false;
    relays = relay.relays or [ ];
    lighthouses =
      if isLighthouse then
        [ ]
      else
        [
          lighthouseIp4
          lighthouseIp6
        ];
    listen = {
      host = listenHost;
      port = listenPort;
    };
    tun = {
      device = interfaceName;
      disable = isLighthouse;
    };
    firewall = {
      outbound = renderedNetwork.settings.nebulaFirewallRules.outbound or [ ];
      inbound = renderedNetwork.settings.nebulaFirewallRules.inbound or [ ];
    };
    settings = {
      static_map.network = "ip";
      relay = {
        am_relay = relay.amRelay or false;
        use_relays = relay.useRelays or false;
        relays = relay.relays or [ ];
      };
      tun = {
        mtu = 1200;
        drop_multicast = false;
      }
      // (renderedNetwork.settings.tun or { });
    };
  };

  systemd.services."nebula@${networkName}" = {
    after = [ "network.target" ];
    serviceConfig = {
      User = lib.mkForce "root";
      Group = lib.mkForce "root";
    };
    unitConfig = {
      AssertPathExists = [
        "${pkiBase}/ca.crt"
        "${pkiBase}/${nodeName}.crt"
        "${pkiBase}/${nodeName}.key"
      ];
    };
  };
}
