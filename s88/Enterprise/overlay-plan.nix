{ lib
, helpers
, caName
, entry
,
}:

let
  inherit (helpers)
    readPrefixLength
    requireAttr
    requireString
    sortedAttrNames
    stripPrefixLength
    uniqueStrings
    withPrefixLength
    ;

  inherit (entry)
    enterpriseName
    siteName
    siteCpm
    cpmData
    overlayName
    overlayCpm
    ;

  overlayId = "${enterpriseName}::${siteName}::${overlayName}";
  basePath = "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}";
  overlayNodes = requireAttr "${basePath}.nodes" (overlayCpm.nodes or null);
  nebula = requireAttr "${basePath}.nebula" (overlayCpm.nebula or null);
  lighthouse = requireAttr "${basePath}.nebula.lighthouse" (nebula.lighthouse or null);
  lighthouseNodeName = requireString "${basePath}.nebula.lighthouse.node" (lighthouse.node or null);
  # The lighthouse may be a node of another site (peer/client site), so its
  # overlay address is carried on the lighthouse block itself. Fall back to a
  # local node only when the lighthouse actually is this site's node.
  lighthouseNode =
    if builtins.hasAttr lighthouseNodeName overlayNodes then overlayNodes.${lighthouseNodeName} else { };
  ipam = requireAttr "${basePath}.ipam" (overlayCpm.ipam or null);
  ipam4 = requireAttr "${basePath}.ipam.ipv4" (ipam.ipv4 or null);
  ipam6 = requireAttr "${basePath}.ipam.ipv6" (ipam.ipv6 or null);
  prefixLength4 = readPrefixLength (requireString "${basePath}.ipam.ipv4.prefix" (ipam4.prefix or null));
  prefixLength6 = readPrefixLength (requireString "${basePath}.ipam.ipv6.prefix" (ipam6.prefix or null));

  # Runtime node config comes from CPM passthrough (overlayCpm.runtimeNodes)
  runtimeNodes = overlayCpm.runtimeNodes or { };

  derivedNebulaRuntimeNodes = import ./derived-runtime-routes.nix {
    inherit
      lib
      helpers
      cpmData
      siteCpm
      overlayName
      overlayCpm
      ;
  };
  explicitNebulaRuntimeNodes = if builtins.isAttrs (nebula.runtimeNodes or null) then nebula.runtimeNodes else { };
  nebulaRuntimeNodes =
    builtins.mapAttrs
      (
        nodeName: derived:
          if builtins.hasAttr nodeName explicitNebulaRuntimeNodes then
            explicitNebulaRuntimeNodes.${nodeName}
          else
            derived
      )
      derivedNebulaRuntimeNodes;

  # A lighthouse may be IPv4-only, IPv6-only, or dual-stack; require at least
  # one modeled endpoint family (SMS-010 lighthouse data).
  endpoint = lighthouse.endpoint or "";
  endpoint6 = lighthouse.endpoint6 or "";
  port = builtins.toString (lighthouse.port or (throw "FS-460-HDS-010-SDS-010-SMS-010: overlay ${overlayName} lighthouse missing port from CPM"));
  endpointSourceFile = lighthouse.endpointSourceFile or null;
  endpoint6SourceFile = lighthouse.endpoint6SourceFile or null;
  _hasEndpoint =
    (builtins.isString endpoint && endpoint != "")
    || (builtins.isString endpoint6 && endpoint6 != "")
    || (builtins.isString endpointSourceFile && endpointSourceFile != "")
    || (builtins.isString endpoint6SourceFile && endpoint6SourceFile != "");
  _endpointRequired =
    if _hasEndpoint then
      true
    else
      throw "FS-460-HDS-010-SDS-010-SMS-010: overlay ${overlayName} lighthouse must model at least one underlay endpoint (IPv4 or IPv6)";
  # Overlay addresses are optional per family (a lighthouse may be v4-only,
  # v6-only, or dual-stack). Keep position 0 = v4, 1 = v6; empty when absent.
  lighthouseAddr4 = lighthouse.addr4 or lighthouseNode.addr4 or "";
  lighthouseAddr6 = lighthouse.addr6 or lighthouseNode.addr6 or "";

  lighthousePlan = {
    node = lighthouseNodeName;
    inherit endpoint endpoint6 port;
    endpoints =
      (if endpoint != "" then [ "${endpoint}:${port}" ] else [ ])
      ++ (if endpoint6 != "" then [ "[${endpoint6}]:${port}" ] else [ ]);
    overlayAddresses =
      (if lighthouseAddr4 != "" then [ (withPrefixLength lighthouseAddr4 prefixLength4) ] else [ ])
      ++ (if lighthouseAddr6 != "" then [ (withPrefixLength lighthouseAddr6 prefixLength6) ] else [ ]);
    overlayIps =
      (if lighthouseAddr4 != "" then [ (stripPrefixLength lighthouseAddr4) ] else [ ])
      ++ (if lighthouseAddr6 != "" then [ (stripPrefixLength lighthouseAddr6) ] else [ ]);
  }
  // lib.optionalAttrs (builtins.isString endpointSourceFile && endpointSourceFile != "") {
    inherit endpointSourceFile;
  }
  // lib.optionalAttrs (builtins.isString endpoint6SourceFile && endpoint6SourceFile != "") {
    inherit endpoint6SourceFile;
  };

  localFirewallCidrs =
    let
      tenants = if builtins.isList ((siteCpm.domains or { }).tenants or null) then siteCpm.domains.tenants else [ ];
      tenantCidrs =
        builtins.concatLists (
          map
            (tenant:
              (lib.optional (builtins.isString (tenant.ipv4 or null)) tenant.ipv4)
              ++ (lib.optional (builtins.isString (tenant.ipv6 or null)) tenant.ipv6))
            tenants
        );
    in
    uniqueStrings tenantCidrs;

in
{
  name = overlayId;
  value = {
    type = "nebula";
    name = overlayName;
    inherit enterpriseName siteName overlayId;
    ca = { name = caName; };
    lighthouse = lighthousePlan;
    nodes = import ./runtime-nodes.nix {
      inherit
        lib
        helpers
        enterpriseName
        siteName
        overlayName
        overlayId
        overlayNodes
        runtimeNodes
        nebulaRuntimeNodes
        localFirewallCidrs
        prefixLength4
        prefixLength6
        lighthousePlan
        ;
    };
  };
}
