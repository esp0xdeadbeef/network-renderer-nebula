{ lib, pkgs, nodeName }:

let
  prepareUnderlayRoutes = pkgs.writeShellScript "nebula-runtime-prepare-underlay-routes-${nodeName}" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.iproute2
        pkgs.jq
      ]
    }:$PATH

    config="/persist/etc/nebula/config.yml"
    route_plan="/persist/etc/nebula/route-preparation.json"
    [ -s "$config" ] || exit 1

    if [ ! -s "$route_plan" ]; then
      echo "nebula-runtime: missing rendered route preparation plan: $route_plan" >&2
      exit 1
    fi

    remove_routes="$(jq -r '.removeRoutes[]? // empty' "$route_plan" | sort -u)"
    overlay_hosts="$(jq -r '.overlayHosts[]? // empty' "$route_plan" | sort -u)"
    endpoint_hosts="$(jq -r '.underlayEndpoints[]? // empty' "$route_plan" | sort -u)"
    preserved_routes="$(mktemp)"
    trap 'rm -f "$preserved_routes"' EXIT

    for endpoint in $endpoint_hosts; do
      if printf '%s' "$endpoint" | grep -q ':'; then
        route="$(ip -6 route get "$endpoint" 2>/dev/null || true)"
        dev="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
        via="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')"
        if [ -n "$dev" ] && [ -n "$via" ]; then
          printf '6\t%s\t%s\t%s\n' "$endpoint" "$dev" "$via" >>"$preserved_routes"
        elif [ -n "$dev" ]; then
          printf '6\t%s\t%s\t\n' "$endpoint" "$dev" >>"$preserved_routes"
        fi
      else
        route="$(ip -4 route get "$endpoint" 2>/dev/null || true)"
        dev="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
        via="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')"
        if [ -n "$dev" ] && [ -n "$via" ]; then
          printf '4\t%s\t%s\t%s\n' "$endpoint" "$dev" "$via" >>"$preserved_routes"
        elif [ -n "$dev" ]; then
          printf '4\t%s\t%s\t\n' "$endpoint" "$dev" >>"$preserved_routes"
        fi
      fi
    done

    for route in $remove_routes; do
      if printf '%s' "$route" | grep -q ':'; then
        ip -6 route del "$route" dev nebula1 2>/dev/null || ip -6 route del "$route" 2>/dev/null || true
      else
        ip route del "$route" dev nebula1 2>/dev/null || ip route del "$route" 2>/dev/null || true
      fi
    done

    for host in $overlay_hosts; do
      if printf '%s' "$host" | grep -q ':'; then
        ip -6 route del "$host/128" 2>/dev/null || true
      else
        ip route del "$host/32" 2>/dev/null || true
      fi
    done

    while IFS="$(printf '\t')" read -r family endpoint dev via; do
      [ -n "$endpoint" ] || continue
      if [ "$family" = 6 ]; then
        if [ -n "$dev" ] && [ -n "$via" ]; then
          ip -6 route replace "$endpoint/128" via "$via" dev "$dev"
        elif [ -n "$dev" ]; then
          ip -6 route replace "$endpoint/128" dev "$dev"
        fi
      else
        if [ -n "$dev" ] && [ -n "$via" ]; then
          ip route replace "$endpoint/32" via "$via" dev "$dev"
        elif [ -n "$dev" ]; then
          ip route replace "$endpoint/32" dev "$dev"
        fi
      fi
    done <"$preserved_routes"
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /persist/etc/nebula 0700 root root -"
  ];

  systemd.services.nebula-runtime = {
    description = "Runtime Nebula daemon for ${nodeName}";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStartPre = [
        "${pkgs.bash}/bin/bash -lc 'for _ in $(seq 1 120); do [ -s /persist/etc/nebula/config.yml ] && exit 0; sleep 1; done; exit 1'"
        "${prepareUnderlayRoutes}"
      ];
      ExecStart = "${pkgs.nebula}/bin/nebula -config /persist/etc/nebula/config.yml";
      Restart = "always";
      RestartSec = 2;
      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
      ];
      CapabilityBoundingSet = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
      ];
    };
  };
}
