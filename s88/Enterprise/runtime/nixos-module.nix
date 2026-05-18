{
  lib,
  pkgs,
  nodeName,
  runtimeNode,
  externalRemoteLighthouseEndpoint4SecretPath ? null,
  externalRemoteLighthouseEndpoint6SecretPath ? null,
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
  hasExternalEndpointSecret =
    externalRemoteLighthouseEndpoint4SecretPath != null || externalRemoteLighthouseEndpoint6SecretPath != null;
  secretPathOrEmpty = path: if path == null then "" else path;
  runtimeConfigPath =
    if hasExternalEndpointSecret then "/run/nebula-runtime/runtime.yml" else "/etc/nebula/${networkName}.yml";
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
    preStart = lib.mkIf hasExternalEndpointSecret ''
      set -eu
      install -d -m 0700 /run/nebula-runtime
      cp /etc/nebula/${networkName}.yml ${runtimeConfigPath}
      ${pkgs.python3}/bin/python3 - ${runtimeConfigPath} ${lib.escapeShellArg (secretPathOrEmpty externalRemoteLighthouseEndpoint4SecretPath)} ${lib.escapeShellArg (secretPathOrEmpty externalRemoteLighthouseEndpoint6SecretPath)} ${toString listenPort} <<'PY'
      import sys
      from pathlib import Path

      config_path = Path(sys.argv[1])
      endpoint4_path = sys.argv[2]
      endpoint6_path = sys.argv[3]
      port = sys.argv[4]

      def read_endpoint(path):
          if not path:
              return ""
          value = Path(path).read_text(encoding="utf-8").strip()
          if not value:
              raise SystemExit(f"empty lighthouse endpoint secret: {path}")
          return value

      endpoints = []
      endpoint4 = read_endpoint(endpoint4_path)
      endpoint6 = read_endpoint(endpoint6_path)
      if endpoint4:
          endpoints.append(f"{endpoint4}:{port}")
      if endpoint6:
          endpoints.append(f"'[{endpoint6}]:{port}'")
      if not endpoints:
          raise SystemExit("no lighthouse endpoint secret configured")

      lines = config_path.read_text(encoding="utf-8").splitlines(keepends=True)
      updated = []
      in_static_map = False
      replaced_any = False

      for line in lines:
          if line == "static_host_map:\n":
              in_static_map = True
              updated.append(line)
              continue
          if in_static_map and line and not line.startswith(" "):
              in_static_map = False
              updated.append(line)
              continue
          if in_static_map and line.startswith("  ") and line.endswith(":\n") and not line.startswith("  - "):
              updated.append(line)
              updated.extend(f"  - {endpoint}\n" for endpoint in endpoints)
              replaced_any = True
              continue
          if in_static_map and line.startswith("  - "):
              continue
          updated.append(line)

      if not replaced_any:
          raise SystemExit("static_host_map had no lighthouse entries to replace")
      config_path.write_text("".join(updated), encoding="utf-8")
      PY
    '';
    serviceConfig = {
      ExecStart = lib.mkIf hasExternalEndpointSecret (
        lib.mkForce "${pkgs.nebula}/bin/nebula -config ${runtimeConfigPath}"
      );
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
