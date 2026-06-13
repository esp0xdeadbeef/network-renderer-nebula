{ lib }:

{ forwarding
, hostName
, cpmData
,
}:

let
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  # Find which enterprise::site has runtime targets on this host
  selectedSiteKeys =
    lib.unique (
      lib.filter
        (key: builtins.isString key.enterpriseName && key.enterpriseName != "" && builtins.isString key.siteName && key.siteName != "")
        (
          lib.concatLists (
            lib.mapAttrsToList
              (enterpriseName: enterpriseSites:
                lib.concatLists (
                  lib.mapAttrsToList
                    (siteName: siteData:
                      let
                        targets = attrsOrEmpty (siteData.runtimeTargets or null);
                        hasTargetOnHost = builtins.any
                          (target: ((target.placement or { }).host or null) == hostName)
                          (builtins.attrValues targets);
                      in
                      if hasTargetOnHost then
                        [{ inherit enterpriseName siteName; }]
                      else
                        [ ]
                    )
                    (attrsOrEmpty enterpriseSites)
                )
              )
              (attrsOrEmpty cpmData)
          )
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
