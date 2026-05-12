{
  lib,
  helpers,
  inventory,
}:

let
  realizationNodes = ((inventory.realization or { }).nodes or { });
  realizationNodeValues = map (name: realizationNodes.${name}) (helpers.sortedAttrNames realizationNodes);

  hostForLogicalNode =
    {
      enterpriseName,
      siteName,
      nodeName,
    }:
    let
      matching =
        lib.filter
          (target:
            ((target.logicalNode or { }).enterprise or "") == enterpriseName
            && ((target.logicalNode or { }).site or "") == siteName
            && ((target.logicalNode or { }).name or "") == nodeName
            && builtins.isString (target.host or null)
            && target.host != "")
          realizationNodeValues;
    in
    if matching == [ ] then null else (builtins.head matching).host;
in
{
  runtimeNodeDeploymentHostFor =
    {
      enterpriseName,
      siteName,
      nodeName,
      runtimeNode,
    }:
    let
      explicitHost =
        if builtins.isString (runtimeNode.host or null) then
          runtimeNode.host
        else
          (runtimeNode.container or { }).host or null;
      targetContainer = (runtimeNode.container or { }).targetContainer or null;
      logicalNodeHost = hostForLogicalNode { inherit enterpriseName siteName nodeName; };
      targetContainerHost =
        if builtins.isString targetContainer && targetContainer != "" then
          hostForLogicalNode {
            inherit enterpriseName siteName;
            nodeName = targetContainer;
          }
        else
          null;
    in
    if builtins.isString explicitHost && explicitHost != "" then
      explicitHost
    else if builtins.isString logicalNodeHost && logicalNodeHost != "" then
      logicalNodeHost
    else
      targetContainerHost;
}
