{ lib }:

{ inventory
, hostName
, logicalName
,
}:
let
  realizationNodes = (((inventory.realization or { }).nodes or { }));
  matches =
    lib.filterAttrs
      (
        _nodeName: node:
          (node.host or null) == hostName
          && ((node.logicalNode or { }).name or null) == logicalName
      )
      realizationNodes;
  node =
    if matches == { } then
      throw "network-renderer-nebula: missing ${logicalName} realization node on ${hostName}"
    else
      builtins.head (builtins.attrValues matches);
in
  node.targetContainer or (node.runtimeName or logicalName)
