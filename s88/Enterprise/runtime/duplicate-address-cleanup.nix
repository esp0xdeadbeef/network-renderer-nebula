{
  lib,
  pkgs,
  interfaceName,
  overlayAddresses,
}:

let
  overlayAddressArgs = lib.concatMapStringsSep " " lib.escapeShellArg overlayAddresses;
in
''
  set -eu
  for cidr in ${overlayAddressArgs}; do
    addr="''${cidr%%/*}"
    ${pkgs.iproute2}/bin/ip -o address show |
      ${pkgs.gawk}/bin/awk -v addr="$addr" -v owner="${interfaceName}" '$2 != owner { split($4, candidate, "/"); if (candidate[1] == addr) print $2 " " $4 }' |
      while read -r duplicate_if duplicate_cidr; do
        ${pkgs.iproute2}/bin/ip address delete "$duplicate_cidr" dev "$duplicate_if" || true
      done
  done
''
