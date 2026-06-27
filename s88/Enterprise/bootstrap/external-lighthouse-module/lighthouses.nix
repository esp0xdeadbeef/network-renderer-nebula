{ lib, nebulaRuntimePlan }:

let
  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
  sanitizeName =
    value:
    lib.replaceStrings
      [
        "::"
        ":"
        "."
        "/"
        " "
      ]
      [
        "-"
        "-"
        "-"
        "-"
        "-"
      ]
      value;
  overlayNames = sortedAttrNames (nebulaRuntimePlan.overlays or { });
  toPort = value: builtins.fromJSON (builtins.toString value);
  fingerprintFor =
    overlayId:
    let
      overlay = nebulaRuntimePlan.overlays.${overlayId};
      lighthouse = overlay.lighthouse or { };
      addresses = lighthouse.overlayAddresses or [ ];
    in
    lib.concatStringsSep "|" [
      (builtins.elemAt addresses 0)
      (builtins.elemAt addresses 1)
      (lighthouse.endpoint or "")
      (lighthouse.endpoint6 or "")
      (builtins.toString (lighthouse.port or (throw "network-renderer-nebula: external lighthouse ${overlayId} missing port from CPM")))
    ];
  lighthouseFingerprints = lib.unique (map fingerprintFor overlayNames);
  matchingOverlaysFor = fingerprint:
    lib.filter (overlayId: fingerprint == fingerprintFor overlayId) overlayNames;
  externalFingerprints =
    lib.filter
      (
        fingerprint:
        let
          matching = matchingOverlaysFor fingerprint;
          base = nebulaRuntimePlan.overlays.${builtins.head matching};
        in
          !(builtins.hasAttr (base.lighthouse.node or "") (nebulaRuntimePlan.nodes or { }))
      )
      lighthouseFingerprints;
in
lib.imap0
  (
    index: fingerprint:
    let
      matching = matchingOverlaysFor fingerprint;
      base = nebulaRuntimePlan.overlays.${builtins.head matching};
      logicalName = sanitizeName base.name;
      lighthouseNode = base.lighthouse.node or (throw "FS-460-HDS-010-SDS-010-SMS-041: lighthouse.node required by CPM provider contract, cannot default to lighthouse");
      listenHost = base.lighthouse.listenHost or (throw "FS-460-HDS-010-SDS-010-SMS-041: external lighthouse listenHost required by CPM provider contract, cannot default to [::]");
      certBaseName = "${logicalName}-${lighthouseNode}";
    in
    {
      name = logicalName;
      inherit certBaseName listenHost;
      serviceName = "nebula-lighthouse-${logicalName}";
      interfaceName = "nebula${builtins.toString index}";
      port = toPort (base.lighthouse.port or (throw "FS-460-HDS-010-SDS-010-SMS-041: external lighthouse ${base.name} missing port from CPM"));
      overlayNetwork4 = builtins.elemAt base.lighthouse.overlayAddresses 0;
      overlayNetwork6 = builtins.elemAt base.lighthouse.overlayAddresses 1;
    }
  )
  externalFingerprints
