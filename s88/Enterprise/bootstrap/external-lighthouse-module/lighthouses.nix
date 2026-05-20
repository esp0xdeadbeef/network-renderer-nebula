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
      (builtins.toString (lighthouse.port or 4242))
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
      certBaseName = "${logicalName}-${base.lighthouse.node or "lighthouse"}";
    in
    {
      name = logicalName;
      inherit certBaseName;
      serviceName = "nebula-lighthouse-${logicalName}";
      interfaceName = "nebula${builtins.toString index}";
      port = toPort (base.lighthouse.port or 4242);
      overlayNetwork4 = builtins.elemAt base.lighthouse.overlayAddresses 0;
      overlayNetwork6 = builtins.elemAt base.lighthouse.overlayAddresses 1;
    }
  )
  externalFingerprints
