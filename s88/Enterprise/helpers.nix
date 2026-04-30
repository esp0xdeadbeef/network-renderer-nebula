{ lib }:

let
  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
in
rec {
  inherit sortedAttrNames;

  requireAttr =
    path: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nebula: missing attrset at ${path}";

  requireString =
    path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nebula: missing string at ${path}";

  stripPrefixLength =
    cidr:
    let
      match = builtins.match "([^/]+)/[0-9]+" cidr;
    in
    if match == null then
      throw "network-renderer-nebula: expected CIDR, got ${builtins.toJSON cidr}"
    else
      builtins.head match;

  readPrefixLength =
    cidr:
    let
      match = builtins.match "[^/]+/([0-9]+)" cidr;
    in
    if match == null then
      throw "network-renderer-nebula: expected CIDR prefix length, got ${builtins.toJSON cidr}"
    else
      builtins.fromJSON (builtins.head match);

  withPrefixLength = cidr: prefixLength: "${stripPrefixLength cidr}/${builtins.toString prefixLength}";

  uniqueStrings = values: lib.unique (lib.filter (value: builtins.isString value && value != "") values);

  collectHostUplinkBridgeNames =
    inventory:
    let
      hosts = ((inventory.deployment or { }).hosts or { });
    in
    lib.unique (
      builtins.concatLists (
        map (
          hostName:
          let
            host = hosts.${hostName};
            uplinks = host.uplinks or { };
          in
          map (uplinkName: uplinks.${uplinkName}.bridge or null) (sortedAttrNames uplinks)
        ) (sortedAttrNames hosts)
      )
    );
}
