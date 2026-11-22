{ lib
, helpers
, cpmData
,
}:

let
  inherit (helpers) requireAttr sortedAttrNames;

  overlayEntries = builtins.concatLists (
    map
      (
        enterpriseName:
        let
          enterpriseCpm =
            requireAttr "canonical site tree ${enterpriseName}" (cpmData.${enterpriseName} or null);
        in
        builtins.concatLists (
          map
            (
              siteName:
              let
                siteCpm =
                  requireAttr "canonical site tree ${enterpriseName}.${siteName}" (enterpriseCpm.${siteName} or null);
                overlays = siteCpm.overlays or { };
              in
              map
                (
                  overlayName:
                  let
                    overlayCpm =
                      requireAttr "canonical site tree ${enterpriseName}.${siteName}.overlays.${overlayName}"
                        (overlays.${overlayName} or null);
                  in
                  {
                    inherit
                      enterpriseName
                      siteName
                      siteCpm
                      cpmData
                      overlayName
                      overlayCpm
                      ;
                  }
                )
                (sortedAttrNames overlays)
            )
            (sortedAttrNames enterpriseCpm)
        )
      )
      (sortedAttrNames cpmData)
  );
in
lib.filter
  (
    entry:
    let
      provider = entry.overlayCpm.provider or null;
    in
    builtins.isString provider && provider == "nebula"
  )
  overlayEntries
