{ lib
, helpers
,
}:

let
  inherit (helpers)
    requireAttr
    requireString
    stripPrefixLength
    ;

  requirePublicEndpointList = path: value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      throw "${path} must be a list";

  publicEndpointSpecsFor =
    nodes: relayNodeName:
    let
      relayNode = requireAttr "nebula.nodes.${relayNodeName}" (nodes.${relayNodeName} or null);
      relayService = relayNode.service or { };
      defaultPort = builtins.toString (relayService.port or relayNode.lighthouse.port or (throw "network-renderer-nebula: relay node ${relayNodeName} missing port from CPM"));
      endpointPath = "nebula.nodes.${relayNodeName}.service.publicEndpoints";
    in
    map
      (entry:
      if !builtins.isAttrs entry then
        throw "${endpointPath}[] must be an attribute set"
      else
        {
          port = builtins.toString (entry.port or defaultPort);
        }
        // lib.optionalAttrs (builtins.isString (entry.endpoint or null) && entry.endpoint != "") {
          endpoint = entry.endpoint;
        }
        // lib.optionalAttrs (builtins.isString (entry.endpointSourceFile or null) && entry.endpointSourceFile != "") {
          sourceFile = entry.endpointSourceFile;
        })
      (requirePublicEndpointList endpointPath (relayService.publicEndpoints or null));

  overlayIp4For =
    nodes: relayNodeName:
    let
      relayNode = requireAttr "nebula.nodes.${relayNodeName}" (nodes.${relayNodeName} or null);
    in
    stripPrefixLength (
      requireString "nebula.nodes.${relayNodeName}.overlayAddresses[0]" (builtins.elemAt relayNode.overlayAddresses 0)
    );

  staticHostMapFor =
    nodes: relayNodeNames:
    builtins.listToAttrs (
      lib.flatten (
        map
          (relayNodeName:
          let
            specs = publicEndpointSpecsFor nodes relayNodeName;
            literalEndpoints =
              map (spec: "${spec.endpoint}:${spec.port}")
                (lib.filter (spec: builtins.isString (spec.endpoint or null) && spec.endpoint != "") specs);
            dynamicEndpoints =
              map (spec: "127.0.0.1:${spec.port}")
                (lib.filter (spec: builtins.isString (spec.sourceFile or null) && spec.sourceFile != "") specs);
          in
          lib.optional (literalEndpoints != [ ] || dynamicEndpoints != [ ]) {
            name = overlayIp4For nodes relayNodeName;
            value = literalEndpoints ++ dynamicEndpoints;
          })
          relayNodeNames
      )
    );

  staticHostMapSecretEndpointsFor =
    nodes: relayNodeNames:
    builtins.listToAttrs (
      lib.flatten (
        map
          (relayNodeName:
          let
            specs = publicEndpointSpecsFor nodes relayNodeName;
            dynamicSpecs = lib.filter (spec: builtins.isString (spec.sourceFile or null) && spec.sourceFile != "") specs;
          in
          lib.optional (dynamicSpecs != [ ]) {
            name = overlayIp4For nodes relayNodeName;
            value = dynamicSpecs;
          })
          relayNodeNames
      )
    );
in
{
  addToNode =
    nodes: node:
    let
      relayNodeNames = (node.relay or { }).nodes or [ ];
    in
    node
    // {
      staticHostMap = (node.staticHostMap or { }) // staticHostMapFor nodes relayNodeNames;
      staticHostMapSecretEndpoints =
        (node.staticHostMapSecretEndpoints or { }) // staticHostMapSecretEndpointsFor nodes relayNodeNames;
    };
}
