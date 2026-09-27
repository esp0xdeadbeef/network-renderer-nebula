{ lib }:

# FS-310-HDS-010-SDS-010-SMS-110 (renderer fail-closed contract): every
# renderer diagnostic names its owning trace id so a failure is traceable to
# the requirement it violates.
let
  traceId = "FS-310-HDS-010-SDS-010-SMS-110";
  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
in
rec {
  inherit sortedAttrNames;

  requireAttr =
    path: value:
    if builtins.isAttrs value then
      value
    else
      throw "${traceId}: missing attrset at ${path}";

  requireString =
    path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "${traceId}: missing string at ${path}";

  stripPrefixLength =
    cidr:
    let
      match = builtins.match "([^/]+)/[0-9]+" cidr;
    in
    if match == null then
      throw "${traceId}: expected CIDR, got ${builtins.toJSON cidr}"
    else
      builtins.head match;

  readPrefixLength =
    cidr:
    let
      match = builtins.match "[^/]+/([0-9]+)" cidr;
    in
    if match == null then
      throw "${traceId}: expected CIDR prefix length, got ${builtins.toJSON cidr}"
    else
      builtins.fromJSON (builtins.head match);

  withPrefixLength = cidr: prefixLength: "${stripPrefixLength cidr}/${builtins.toString prefixLength}";

  uniqueStrings = values: lib.unique (lib.filter (value: builtins.isString value && value != "") values);
}
