{ lib }:

{ forwarding
, hostName
, inventory
,
}:
let
  realizationNodes = (((inventory.realization or { }).nodes or { }));
  selectedSiteKeys =
    lib.unique (
      lib.filter
        (key: key.enterpriseName != "" && key.siteName != "")
        (
          lib.mapAttrsToList
            (
              _nodeName: node:
                if (node.host or null) == hostName then
                  {
                    enterpriseName = (node.logicalNode or { }).enterprise or "";
                    siteName = (node.logicalNode or { }).site or "";
                  }
                else
                  {
                    enterpriseName = "";
                    siteName = "";
                  }
            )
            realizationNodes
        )
    );
  selectedSite =
    if builtins.length selectedSiteKeys == 1 then
      builtins.head selectedSiteKeys
    else
      throw "network-renderer-nebula: ${hostName} must map to exactly one enterprise/site for host NAT ingress";
  enterpriseName = selectedSite.enterpriseName;
  siteName = selectedSite.siteName;
  forwardingSite = (((forwarding.enterprise or { }).${enterpriseName} or { }).site.${siteName} or { });
  hostNatIngress =
    if builtins.isAttrs (forwardingSite.hostNatIngress or null) && forwardingSite.hostNatIngress != { } then
      forwardingSite.hostNatIngress
    else
      throw "network-renderer-nebula: forwarding output must provide ${enterpriseName}.${siteName}.hostNatIngress";
in
{
  inherit enterpriseName siteName hostNatIngress;
  targetNode =
    if hostNatIngress.enabled or false then
      hostNatIngress.targetNode or (throw "network-renderer-nebula: ${enterpriseName}.${siteName}.hostNatIngress.targetNode is required")
    else
      null;
  uplink =
    if hostNatIngress.enabled or false then
      hostNatIngress.uplink or (throw "network-renderer-nebula: ${enterpriseName}.${siteName}.hostNatIngress.uplink is required")
    else
      null;
}
