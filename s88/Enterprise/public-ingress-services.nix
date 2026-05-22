{ lib }:

{ enterpriseName
, hostNatIngressTargetWan
, lighthousePublicIPv4SecretPath
, lighthouseServiceName
, site
,
}:
let
  endpoint4ForService = serviceName: serviceDef:
    let
      endpoints = serviceDef.providerEndpoints or [ ];
      endpoint =
        if builtins.length endpoints == 1 then
          builtins.head endpoints
        else
          throw "network-renderer-nebula: service ${serviceName} must have exactly one provider endpoint";
      addresses = endpoint.ipv4 or [ ];
    in
    if builtins.length addresses == 1 then
      builtins.head addresses
    else
      throw "network-renderer-nebula: service ${serviceName} provider endpoint must have exactly one IPv4 address";
  isWanExternal = endpoint:
    (endpoint.kind or null) == "external"
    && ((endpoint.name or null) == "wan" || builtins.elem "wan" (endpoint.uplinks or [ ]));
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
  serviceNames = lib.unique ([ lighthouseServiceName ] ++ wanServiceNames);
in
builtins.listToAttrs (
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
)
