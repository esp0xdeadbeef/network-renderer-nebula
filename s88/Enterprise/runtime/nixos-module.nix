{ lib
, pkgs
, nodeName
, runtimeNode
, externalRemoteLighthouseEndpoint4SecretPath ? null
, externalRemoteLighthouseEndpoint6SecretPath ? null
,
}:

let
  networkName = "runtime";
  interfaceName = runtimeNode.service.interface or (throw "network-renderer-nebula: runtime node ${nodeName} missing service.interface from CPM");
  pkiBase = "/persist/nebula-runtime/profiles/${nodeName}";
  isLighthouse = (runtimeNode.lighthouse.node or null) == nodeName;
  lighthouseIps = runtimeNode.lighthouse.overlayIps or [ ];
  lighthouseIp4 = builtins.elemAt lighthouseIps 0;
  lighthouseIp6 = builtins.elemAt lighthouseIps 1;
  lighthouseEndpoints = runtimeNode.lighthouse.endpoints or [ ];
  overlayAddresses = runtimeNode.overlayAddresses or [ ];
  duplicateAddressCleanup = import ./duplicate-address-cleanup.nix {
    inherit
      lib
      pkgs
      interfaceName
      overlayAddresses
      ;
  };
  renderedNetwork = runtimeNode.nebulaNetwork or {
    settings = { };
  };
  dynamicFirewallCidrs =
    if builtins.isList (runtimeNode.dynamicFirewallCidrs or null) then
      runtimeNode.dynamicFirewallCidrs
    else
      [ ];
  dynamicUnsafeRoutes =
    if builtins.isList (runtimeNode.dynamicUnsafeRoutes or null) then
      runtimeNode.dynamicUnsafeRoutes
    else
      [ ];
  renderedStaticHostMap = runtimeNode.staticHostMap or { };
  staticHostMapSecretEndpoints = runtimeNode.staticHostMapSecretEndpoints or { };
  lighthouseStaticHostMap =
    if isLighthouse then
      { }
    else
      {
        ${lighthouseIp4} = lighthouseEndpoints;
        ${lighthouseIp6} = lighthouseEndpoints;
      };
  staticHostMap =
    renderedStaticHostMap
    // lib.filterAttrs (address: _: !(builtins.hasAttr address renderedStaticHostMap)) lighthouseStaticHostMap;
  relay = runtimeNode.relay or { };
  listenHost = runtimeNode.service.listenHost or "[::]";
  rawListenPort = runtimeNode.service.port or runtimeNode.lighthouse.port or (throw "network-renderer-nebula: runtime node ${nodeName} missing service.port or lighthouse.port from CPM");
  listenPort = if builtins.isInt rawListenPort then rawListenPort else lib.toInt rawListenPort;
  rawLighthousePort = runtimeNode.lighthouse.port or (throw "network-renderer-nebula: runtime node ${nodeName} missing lighthouse.port from CPM");
  lighthousePort = if builtins.isInt rawLighthousePort then rawLighthousePort else lib.toInt rawLighthousePort;
  hasExternalEndpointSecret =
    !isLighthouse
    && (externalRemoteLighthouseEndpoint4SecretPath != null || externalRemoteLighthouseEndpoint6SecretPath != null);
  hasDynamicStaticHostMap = hasExternalEndpointSecret || staticHostMapSecretEndpoints != { };
  hasDynamicFirewallCidrs = dynamicFirewallCidrs != [ ];
  hasDynamicUnsafeRoutes = dynamicUnsafeRoutes != [ ];
  hasDynamicRuntimeConfig = hasDynamicStaticHostMap || hasDynamicFirewallCidrs || hasDynamicUnsafeRoutes;
  runtimeConfigPath =
    if hasDynamicRuntimeConfig then "/run/nebula-runtime/runtime.yml" else "/etc/nebula/${networkName}.yml";
  staticHostMapSecretEndpointsJson = builtins.toJSON staticHostMapSecretEndpoints;
  dynamicStaticHostMapPreStart = import ./dynamic-static-host-map-prestart.nix {
    inherit
      lib
      pkgs
      networkName
      runtimeConfigPath
      externalRemoteLighthouseEndpoint4SecretPath
      externalRemoteLighthouseEndpoint6SecretPath
      listenPort
      lighthouseIp4
      lighthouseIp6
      staticHostMapSecretEndpointsJson
      listenHost
      lighthousePort
      ;
  };
  dynamicFirewallCidrsPreStart = import ./dynamic-firewall-cidrs-prestart.nix {
    inherit lib pkgs runtimeConfigPath;
    dynamicFirewallCidrsJson = builtins.toJSON dynamicFirewallCidrs;
  };
  dynamicUnsafeRoutesPreStart = import ./dynamic-unsafe-routes-prestart.nix {
    inherit lib pkgs runtimeConfigPath;
    dynamicUnsafeRoutesJson = builtins.toJSON dynamicUnsafeRoutes;
  };
in
{
  systemd.tmpfiles.rules = [
    "d /persist/nebula-runtime 0700 root root -"
    "d /persist/nebula-runtime/profiles 0700 root root -"
    "d ${pkiBase} 0700 root root -"
  ];

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
        mtu = runtimeNode.nebulaNetwork.settings.tun.mtu or runtimeNode.service.mtu or (throw "network-renderer-nebula: runtime node ${nodeName} missing tun MTU from CPM (nebulaNetwork.settings.tun.mtu or service.mtu)");
        drop_multicast = false;
      }
      // (renderedNetwork.settings.tun or { });
    };
  };

  systemd.services."nebula@${networkName}" = {
    after = [ "network.target" ];
    preStart =
      duplicateAddressCleanup
      + lib.optionalString hasDynamicStaticHostMap dynamicStaticHostMapPreStart
      + lib.optionalString hasDynamicFirewallCidrs dynamicFirewallCidrsPreStart
      + lib.optionalString hasDynamicUnsafeRoutes dynamicUnsafeRoutesPreStart;
    serviceConfig = {
      ExecStart = lib.mkIf hasDynamicRuntimeConfig (
        lib.mkForce "${pkgs.nebula}/bin/nebula -config ${runtimeConfigPath}"
      );
      RuntimeDirectory = lib.mkIf hasDynamicRuntimeConfig "nebula-runtime";
      ReadWritePaths = lib.mkIf hasDynamicRuntimeConfig [ "/run/nebula-runtime" ];
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
