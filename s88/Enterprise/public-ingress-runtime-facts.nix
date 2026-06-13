{ lib }:

{ controlPlane
, forwarding
, hostName
, inventory
, hostNatIngressTargetWan
, lighthousePublicIPv4SecretPath
, runtimePublicIPv4SecretPath
, runtimeContainerName
, runtimeNode
, runtimeForwardInterfaceName ? "public-ingress"
, runtimeForwardHostBridge ? "br-wan"
,
}:
let
  cpmRoot =
    if builtins.isAttrs (controlPlane.control_plane_model.data or null) then
      controlPlane.control_plane_model.data
    else if builtins.isAttrs (controlPlane.data or null) then
      controlPlane.data
    else
      throw "network-renderer-nebula: controlPlane.control_plane_model.data is required";
  realizationNodes = (((inventory.realization or { }).nodes or { }));
  selectedSiteKeys =
    lib.unique (
      lib.filter
        (key: builtins.isString key.enterpriseName && key.enterpriseName != "" && builtins.isString key.siteName && key.siteName != "")
        (
          lib.mapAttrsToList
            (
              _nodeName: node:
                if (node.host or null) == hostName then
                  {
                    enterpriseName = (node.logicalNode or { }).enterprise or null;
                    siteName = (node.logicalNode or { }).site or null;
                  }
                else
                  {
                    enterpriseName = null;
                    siteName = null;
                  }
            )
            realizationNodes
        )
    );
  selectedSite =
    if builtins.length selectedSiteKeys == 1 then
      builtins.head selectedSiteKeys
    else
      throw "network-renderer-nebula: ${hostName} must map to exactly one enterprise/site for public ingress runtime facts";
  enterpriseName = selectedSite.enterpriseName;
  siteName = selectedSite.siteName;
  forwardingSite = (((forwarding.enterprise or { }).${enterpriseName} or { }).site.${siteName} or { });
  hostNatIngress =
    if builtins.isAttrs (forwardingSite.hostNatIngress or null) && forwardingSite.hostNatIngress != { } then
      forwardingSite.hostNatIngress
    else
      throw "network-renderer-nebula: forwarding output must provide ${enterpriseName}.${siteName}.hostNatIngress";
  reservedTcpDports =
    lib.sort (a: b: a < b) (
      lib.unique (
        lib.concatMap
          (port:
            if (port.proto or null) == "tcp" then
              port.dports or [ ]
            else
              [ ])
          (hostNatIngress.hostReservedPorts or [ ])
      )
    );
  runtimeForwardAddress4Bare =
    let
      listenHost = runtimeNode.service.listenHost or null;
    in
    if
      builtins.isString listenHost
      && listenHost != ""
      && builtins.length (lib.splitString ":" listenHost) == 1
      && builtins.length (lib.splitString "/" listenHost) == 1
    then
      listenHost
    else
      throw "network-renderer-nebula: runtimeNode.service.listenHost must provide a bare IPv4 address for ${runtimeContainerName}";
  hostNatIngressPrefixLength4 =
    let
      parts = lib.splitString "/" hostNatIngressTargetWan.hostAddress4;
    in
    if builtins.length parts == 2 && builtins.elemAt parts 1 != "" then
      builtins.elemAt parts 1
    else
      throw "network-renderer-nebula: hostNatIngressTargetWan.hostAddress4 must be a CIDR address";
  runtimeForwardAddress4 = "${runtimeForwardAddress4Bare}/${hostNatIngressPrefixLength4}";
  runtimeForwardDports =
    let
      port = runtimeNode.service.port or null;
    in
    if builtins.isInt port then
      [ port ]
    else
      throw "network-renderer-nebula: runtimeNode.service.port must provide an integer public runtime UDP port for ${runtimeContainerName}";
  site = ((cpmRoot.${enterpriseName} or { }).${siteName} or { });
  service =
    let
      services = site.services or [ ];
      matches =
        builtins.filter
          (item:
            (item.trafficType or null) == "nebula"
            && builtins.isString (item.name or null)
            && (item.providerEndpoints or [ ]) != [ ])
          services;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      throw "network-renderer-nebula: expected exactly one ${enterpriseName}.${siteName} service with trafficType=nebula and provider endpoint";
  lighthouseServiceName = service.name;
  endpoint4 =
    let
      endpoints = service.providerEndpoints or [ ];
      endpoint =
        if builtins.length endpoints == 1 then
          builtins.head endpoints
        else
          throw "network-renderer-nebula: service ${lighthouseServiceName} must have exactly one provider endpoint";
      addresses = endpoint.ipv4 or [ ];
    in
    if builtins.length addresses == 1 then
      builtins.head addresses
    else
      throw "network-renderer-nebula: service ${lighthouseServiceName} provider endpoint must have exactly one IPv4 address";
  publicIngressServices = import ./public-ingress-services.nix { inherit lib; } {
    inherit enterpriseName hostNatIngressTargetWan lighthousePublicIPv4SecretPath lighthouseServiceName site;
  };
in
{
  localLighthouseEndpoint4 = endpoint4;
  publicIngress = {
    snatSourceCidr4 = hostNatIngressTargetWan.hostAddress4;
    services.${enterpriseName}.${siteName} = publicIngressServices.services;
    unsupportedServices.${enterpriseName}.${siteName} = publicIngressServices.unsupportedWanServices;
    runtimeForwards = [
      {
        publicIPv4SecretPath = runtimePublicIPv4SecretPath;
        targetIPv4 = runtimeForwardAddress4Bare;
        protocols = [ "udp" ];
        inputDports = runtimeForwardDports;
        protectServiceDports = false;
        exceptTcpDports = reservedTcpDports;
        containerInterface = {
          container = runtimeContainerName;
          name = runtimeForwardInterfaceName;
          hostBridge = runtimeForwardHostBridge;
          localAddress = runtimeForwardAddress4;
          gateway4 = hostNatIngressTargetWan.hostGateway4;
          inputDports = runtimeForwardDports;
        };
      }
    ];
  };
}
