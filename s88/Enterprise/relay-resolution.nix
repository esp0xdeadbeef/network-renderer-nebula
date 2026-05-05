{ helpers, rawNodes }:

let
  nodeOverlayIp4 = nodeName:
    let
      node =
        if builtins.hasAttr nodeName rawNodes then
          rawNodes.${nodeName}
        else
          throw ''
            network-renderer-nebula: runtimeNodes.*.relay.relays references unknown runtime node '${nodeName}'

            Model relay targets as runtimeNodes in inventory so the renderer can resolve them to explicit Nebula overlay addresses.
          '';
    in
    helpers.stripPrefixLength (builtins.elemAt node.overlayAddresses 0);

  relayForNode =
    nodeName: node:
    let
      relay = node.relay or { };
      relayNames = relay.relays or [ ];
      amRelay = relay.amRelay or false;
      useRelays = relay.useRelays or (relayNames != [ ]);
      relays = map nodeOverlayIp4 relayNames;
      _relayShape =
        if !(builtins.isBool amRelay) then
          throw "network-renderer-nebula: runtimeNodes.${nodeName}.relay.amRelay must be a boolean"
        else if !(builtins.isBool useRelays) then
          throw "network-renderer-nebula: runtimeNodes.${nodeName}.relay.useRelays must be a boolean"
        else if !(builtins.isList relayNames) || !(builtins.all builtins.isString relayNames) then
          throw "network-renderer-nebula: runtimeNodes.${nodeName}.relay.relays must be a list of runtime node names"
        else if amRelay && relayNames != [ ] then
          throw "network-renderer-nebula: runtimeNodes.${nodeName}.relay cannot set amRelay=true and also list relays; Nebula does not support relaying to a relay"
        else
          true;
      _relayTargets =
        builtins.all (
          relayName:
          let
            target = rawNodes.${relayName} or null;
          in
          if target == null then
            false
          else if (target.relay.amRelay or false) != true then
            throw "network-renderer-nebula: runtimeNodes.${nodeName}.relay.relays includes '${relayName}', but that runtime node does not set relay.amRelay=true"
          else
            true
        ) relayNames;
    in
    builtins.seq _relayShape (
      builtins.seq _relayTargets {
        inherit amRelay useRelays relays;
        nodes = relayNames;
      }
    );
in
{
  inherit relayForNode;
}
