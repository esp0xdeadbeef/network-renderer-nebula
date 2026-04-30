{
  lib,
  helpers,
  inventory,
  cpmData,
}:

let
  inherit (helpers) requireAttr sortedAttrNames;

  inventorySites = ((inventory.controlPlane or { }).sites or { });

  overlayEntries = builtins.concatLists (
    map (
      enterpriseName:
      let
        enterpriseInventory =
          requireAttr "inventory.controlPlane.sites.${enterpriseName}" (inventorySites.${enterpriseName} or null);
        enterpriseCpm = requireAttr "control_plane_model.data.${enterpriseName}" (cpmData.${enterpriseName} or null);
      in
      builtins.concatLists (
        map (
          siteName:
          let
            siteInventory =
              requireAttr "inventory.controlPlane.sites.${enterpriseName}.${siteName}"
                (enterpriseInventory.${siteName} or null);
            siteCpm =
              requireAttr "control_plane_model.data.${enterpriseName}.${siteName}" (enterpriseCpm.${siteName} or null);
            overlays = siteInventory.overlays or { };
          in
          map (
            overlayName:
            let
              overlayInventory =
                requireAttr "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}"
                  (overlays.${overlayName} or null);
              overlayCpm =
                requireAttr "control_plane_model.data.${enterpriseName}.${siteName}.overlays.${overlayName}"
                  ((siteCpm.overlays or { }).${overlayName} or null);
            in
            {
              inherit
                enterpriseName
                siteName
                overlayName
                overlayInventory
                overlayCpm
                ;
            }
          ) (sortedAttrNames overlays)
        ) (sortedAttrNames enterpriseInventory)
      )
    ) (sortedAttrNames inventorySites)
  );
in
lib.filter (
  entry:
  let
    provider = entry.overlayInventory.provider or entry.overlayCpm.provider or null;
  in
  builtins.isString provider && provider == "nebula"
) overlayEntries
