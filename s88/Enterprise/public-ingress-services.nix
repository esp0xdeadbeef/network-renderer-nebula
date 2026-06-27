{ lib }:

{ enterpriseName
, hostNatIngressTargetWan
, lighthousePublicIPv4SecretPath
, lighthouseServiceName
, site
,
}:
let
  endpoint4OrNull = serviceDef:
    let
      endpoints = serviceDef.providerEndpoints or [ ];
      endpoint = if builtins.length endpoints == 1 then builtins.head endpoints else { };
      addresses = endpoint.ipv4 or [ ];
    in
    if builtins.length addresses == 1 then builtins.head addresses else null;
  endpoint4ForService = serviceName: serviceDef:
    let
      endpoint4 = endpoint4OrNull serviceDef;
    in
    if endpoint4 != null then
      endpoint4
    else
      throw "network-renderer-nebula: service ${serviceName} provider endpoint must have exactly one IPv4 address";
  isWanExternal = endpoint:
    (endpoint.kind or null) == "external"
    && ((endpoint.trafficClass or null) == "internet-egress" || (endpoint.egressSurface or null) != null);
  relationTargetServiceName = relation:
    let
      target = relation.to or { };
    in
    if (target.kind or null) == "service" && builtins.isString (target.name or null) && target.name != "" then
      target.name
    else
      null;
  wanServiceNames =
    lib.unique (
      builtins.filter
        (name: name != null)
        (map
          relationTargetServiceName
          (builtins.filter
            (relation: (relation.action or null) == "allow" && isWanExternal (relation.from or { }))
            (site.relations or ((site.communicationContract or { }).allowedRelations or [ ]))))
    );
  serviceByName =
    builtins.listToAttrs (
      map
        (item: {
          name = item.name;
          value = item;
        })
        (builtins.filter (item: builtins.isString (item.name or null) && item.name != "") (site.services or [ ]))
    );
  wanServiceRecords =
    map
      (serviceName:
      let
        serviceDef =
          serviceByName.${serviceName}
            or (throw "network-renderer-nebula: public ingress service ${enterpriseName}.${serviceName} is missing from CPM services");
      in
      {
        inherit serviceName serviceDef;
        endpoint4 = endpoint4OrNull serviceDef;
      })
      wanServiceNames;
  compatibleWanServiceNames =
    map
      (record: record.serviceName)
      (builtins.filter (record: record.endpoint4 != null) wanServiceRecords);
  unsupportedWanServices =
    map
      (record: {
        name = record.serviceName;
        reason = "provider endpoint does not have exactly one IPv4 address for Nebula public-ingress materialization";
      })
      (builtins.filter (record: record.endpoint4 == null) wanServiceRecords);
  serviceNames = lib.unique ([ lighthouseServiceName ] ++ compatibleWanServiceNames);
in
{
  services = builtins.listToAttrs (
    map
      (serviceName:
      let
        serviceDef =
          serviceByName.${serviceName}
            or (throw "network-renderer-nebula: public ingress service ${enterpriseName}.${serviceName} is missing from CPM services");
        _endpoint4 = endpoint4ForService serviceName serviceDef;
      in
      {
        name = serviceName;
        value = {
          publicIPv4SecretPath = lighthousePublicIPv4SecretPath;
          gateway4 = hostNatIngressTargetWan.coreAddress4Bare;
        };
      })
      serviceNames
  );
  inherit unsupportedWanServices;
}
