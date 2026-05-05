cleanup() {
  rm -f "$signing_ca_key"
}
trap cleanup EXIT

mkdir -p "$pki_dir"
printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
  mkdir -p "$profiles_dir/$node_name"
done

issue_node_cert() {
  local cert_name="$1"
  local node_networks="$2"
  local node_groups="$3"
  local node_unsafe_networks="${4:-}"
  local cert_path="$pki_dir/$cert_name.crt"
  local key_path="$pki_dir/$cert_name.key"

  rm -f "$cert_path" "$key_path"
  cert_args=(
    -ca-crt "$pki_dir/ca.crt"
    -ca-key "$signing_ca_key"
    -name "$cert_name"
    -networks "$node_networks"
    -groups "$node_groups"
    -out-crt "$cert_path"
    -out-key "$key_path"
  )
  if [ -n "$node_unsafe_networks" ]; then
    cert_args+=(-unsafe-networks "$node_unsafe_networks")
  fi
  nebula-cert sign "${cert_args[@]}"
}

if [ ! -s "$pki_dir/ca.crt" ] || [ ! -s "$signing_ca_key" ]; then
  echo "nebula-profile-bootstrap: missing unlocked CA material; run nebula-ca-unseal first" >&2
  exit 1
fi

access_prefixes_all() {
  for prefix_file in /run/secrets/access-node-ipv6-prefix-*; do
    [ -s "$prefix_file" ] || continue
    tr -d '[:space:]' <"$prefix_file"
    printf '\n'
  done
}
access_prefix_for_node() {
  local node="$1"
  local prefix_file="/run/secrets/access-node-ipv6-prefix-$node"
  if [ -s "$prefix_file" ]; then
    tr -d '[:space:]' <"$prefix_file"
  fi
}
node_has_default_exit_routes() {
  local node="$1"
  printf '%s' "$runtime_nodes_json" \
    | jq -e --arg n "$node" '
        any(.[$n].unsafeRoutes[]?; .route == "0.0.0.0/1" or .route == "128.0.0.0/1" or .route == "::/1" or .route == "8000::/1")
      ' >/dev/null
}
append_csv() {
  local csv="$1"
  local value="$2"
  [ -n "$value" ] || {
    printf '%s' "$csv"
    return
  }
  if [ -n "$csv" ]; then
    printf '%s,%s' "$csv" "$value"
  else
    printf '%s' "$value"
  fi
}
listen_supports_ipv4() {
  local listen_host="$1"
  case "$listen_host" in
    ""|"*"|"[::]"|"::"|"0.0.0.0")
      return 0
      ;;
    *:*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}
listen_supports_ipv6() {
  local listen_host="$1"
  case "$listen_host" in
    ""|"*"|"[::]"|"::")
      return 0
      ;;
    *:*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
nebula_control_networks_csv() {
  printf '%s\n' "$1" \
    | awk -F, '
        {
          for (i = 1; i <= NF; i++) {
            if ($i != "") {
              out = out ? out "," $i : $i
            }
          }
        }
        END { print out }
      '
}

printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
  cert_cidr4="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$node_name" '.[$n].certCidr4')"
  cert_cidr6="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$node_name" '.[$n].certCidr6')"
  groups_csv="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$node_name" '.[$n].groupsCsv')"
  unsafe_networks="$(
    printf '%s' "$runtime_nodes_json" \
      | jq -r --arg n "$node_name" '.[$n].advertisedUnsafeNetworks | join(",")' \
      | while read -r cidrs; do nebula_control_networks_csv "$cidrs"; done
  )"
  delegated_prefix="$(access_prefix_for_node "$node_name")"
  if [ -n "$delegated_prefix" ]; then
    unsafe_networks="$(append_csv "$unsafe_networks" "$delegated_prefix")"
  fi
  if node_has_default_exit_routes "$node_name"; then
    while read -r delegated_prefix; do
      unsafe_networks="$(append_csv "$unsafe_networks" "$delegated_prefix")"
    done < <(access_prefixes_all)
    while read -r cidr; do
      unsafe_networks="$(append_csv "$unsafe_networks" "$cidr")"
    done < <(printf '%s\n' "$external_lighthouse_return_ipv4_cidrs_csv" | tr ',' '\n' | sed '/^$/d')
  fi
  issue_node_cert "$node_name" "$cert_cidr4,$cert_cidr6" "$groups_csv" "$unsafe_networks"
done

printf '%s' "$lighthouses_json" | jq -r 'keys[]' | while read -r lighthouse_id; do
  if printf '%s' "$lighthouses_json" | jq -e --arg n "$lighthouse_id" '.[$n].internal == true' >/dev/null; then
    continue
  fi
  cert_base_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].certBaseName')"
  cert_networks="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].certNetworks | join(",")')"
  unsafe_networks="$(
    printf '%s' "$lighthouses_json" \
      | jq -r --arg n "$lighthouse_id" '.[$n].unsafeNetworks | join(",")' \
      | while read -r cidrs; do nebula_control_networks_csv "$cidrs"; done
  )"
  issue_node_cert "$cert_base_name" "$cert_networks" "lab,lighthouse" "$unsafe_networks"
done

root_ssh_dir="/persist/root/.ssh"
mkdir -p "$root_ssh_dir"
chmod 0700 "$root_ssh_dir"
if [ ! -s "$root_ssh_dir/id_ed25519" ] || [ ! -s "$root_ssh_dir/id_ed25519.pub" ]; then
  rm -f "$root_ssh_dir/id_ed25519" "$root_ssh_dir/id_ed25519.pub"
  ssh-keygen -q -t ed25519 -N "" -f "$root_ssh_dir/id_ed25519"
fi

install_profile() {
  local profile_name="$1"
  local profile_context="${2:-local}"
  local profile_dir="$profiles_dir/$profile_name"
  local pki_base="/persist/etc/nebula"
  local cert_name="$profile_name.crt"
  local key_name="$profile_name.key"
  local lighthouse_ip4
  local lighthouse_ip6
  local lighthouse_endpoint
  local lighthouse_endpoint6
  local lighthouse_static_host_map_yaml
  local lighthouse_hosts_yaml
  local advertise_addrs_yaml
  local external_static_host_map_yaml
  local port_forward_endpoint
  local port_forward_endpoint6
  local lighthouse_port
  local listen_host
  local is_lighthouse
  local route_preparation_json
  local relay_yaml
  local unsafe_routes_yaml
  local unsafe_fw_rules

  lighthouse_ip4="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.overlayIp4')"
  lighthouse_ip6="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.overlayIp6')"
  lighthouse_endpoint="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.endpoint')"
  lighthouse_endpoint6="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.endpoint6')"
  lighthouse_port="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.port')"
  listen_host="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].service.listenHost // "[::]"')"
  is_lighthouse="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].isLighthouse == true')"
  if [ -n "$external_lighthouse_public_ipv4_secret" ] && [ -s "$external_lighthouse_public_ipv4_secret" ]; then
    lighthouse_endpoint="$(tr -d '[:space:]' <"$external_lighthouse_public_ipv4_secret")"
  fi
  if [ -n "$external_lighthouse_public_ipv6_secret" ] && [ -s "$external_lighthouse_public_ipv6_secret" ]; then
    lighthouse_endpoint6="$(tr -d '[:space:]' <"$external_lighthouse_public_ipv6_secret")"
    lighthouse_endpoint6="${lighthouse_endpoint6%%/*}"
    if printf '%s' "$lighthouse_endpoint6" | grep -q '::$'; then
      lighthouse_endpoint6="${lighthouse_endpoint6}1"
    fi
  fi
  port_forward_endpoint="$lighthouse_endpoint"
  port_forward_endpoint6="$lighthouse_endpoint6"
  if [ -n "$external_port_forward_public_ipv4_secret" ] && [ -s "$external_port_forward_public_ipv4_secret" ]; then
    port_forward_endpoint="$(tr -d '[:space:]' <"$external_port_forward_public_ipv4_secret")"
  fi
  if [ -n "$external_port_forward_public_ipv6_secret" ] && [ -s "$external_port_forward_public_ipv6_secret" ]; then
    port_forward_endpoint6="$(tr -d '[:space:]' <"$external_port_forward_public_ipv6_secret")"
    port_forward_endpoint6="${port_forward_endpoint6%%/*}"
    if printf '%s' "$port_forward_endpoint6" | grep -q '::$'; then
      port_forward_endpoint6="${port_forward_endpoint6}1"
    fi
  fi
  route_lighthouse_endpoint="$lighthouse_endpoint"
  route_lighthouse_endpoint6="$lighthouse_endpoint6"
  if
    [ "$profile_context" != "remote" ] \
    && [ "$external_suppress_public_lighthouse_static_map" = "1" ]
  then
    if [ -n "$external_remote_lighthouse_endpoint4" ]; then
      route_lighthouse_endpoint="$external_remote_lighthouse_endpoint4"
    fi
    if [ -n "$external_remote_lighthouse_endpoint6" ]; then
      route_lighthouse_endpoint6="$external_remote_lighthouse_endpoint6"
    fi
  fi
  if ! listen_supports_ipv4 "$listen_host"; then
    lighthouse_endpoint=""
    route_lighthouse_endpoint=""
    port_forward_endpoint=""
  fi
  if ! listen_supports_ipv6 "$listen_host"; then
    lighthouse_endpoint6=""
    route_lighthouse_endpoint6=""
    port_forward_endpoint6=""
  fi
  unsafe_routes_yaml="$(
    printf '%s' "$runtime_nodes_json" \
      | jq -r --arg n "$profile_name" '
          .[$n].unsafeRoutes
          | map(
              "    - route: \(.route)\n      via: "
              + (
                  if (.route | contains(":")) then
                    (.via6 // .via // "__LIGHTHOUSE_IPV6__")
                  else
                    (.via4 // .via // "__LIGHTHOUSE_IPV4__")
                  end
                )
              + "\n      mtu: "
              + (if (.route | contains(":")) then "1280" else "1200" end)
              + "\n      install: "
              + (if (.install // true) then "true" else "false" end)
            )
          | join("\n")
        '
  )"
  unsafe_fw_rules="$(
    printf '%s' "$runtime_nodes_json" \
      | jq -r --arg n "$profile_name" '
          .[$n].advertisedUnsafeNetworks
          | map(select((endswith("/32") or endswith("/128")) | not))
          | map("    - port: any\n      proto: any\n      host: any\n      local_cidr: \(.)")
          | join("\n")
        '
  )"
  relay_yaml="$(
    printf '%s' "$runtime_nodes_json" \
      | jq -r --arg n "$profile_name" '
          .[$n].relay as $relay
          | "relay:\n"
            + (($relay.relays // [])
              | if length > 0 then
                  "  relays:\n" + (map("    - " + .) | join("\n")) + "\n"
                else
                  ""
                end)
            + "  am_relay: " + (if ($relay.amRelay // false) then "true" else "false" end) + "\n"
            + "  use_relays: " + (if ($relay.useRelays // false) then "true" else "false" end)
        '
  )"

  if node_has_default_exit_routes "$profile_name"; then
    while read -r delegated_prefix; do
      [ -n "$delegated_prefix" ] || continue
      extra_fw_rule="    - port: any
      proto: any
      host: any
      local_cidr: $delegated_prefix"
      if [ -n "$unsafe_fw_rules" ]; then
        unsafe_fw_rules="$unsafe_fw_rules
$extra_fw_rule"
      else
        unsafe_fw_rules="$extra_fw_rule"
      fi
    done < <(access_prefixes_all)
  fi

  if [ -n "$unsafe_routes_yaml" ]; then
    unsafe_routes_yaml="$(printf '%s\n' "$unsafe_routes_yaml" | sed "s/__LIGHTHOUSE_IPV4__/${lighthouse_ip4}/g; s/__LIGHTHOUSE_IPV6__/${lighthouse_ip6}/g")"
  fi
  route_preparation_json="$(
    printf '%s' "$runtime_nodes_json" \
          | jq -c \
          --arg n "$profile_name" \
          --arg endpoint4 "$route_lighthouse_endpoint" \
          --arg endpoint6 "$route_lighthouse_endpoint6" \
          --arg portForwardEndpoint4 "$port_forward_endpoint" \
          --arg portForwardEndpoint6 "$port_forward_endpoint6" \
          --arg overlay4 "$lighthouse_ip4" \
          --arg overlay6 "$lighthouse_ip6" '
            .[$n] as $node
            | ($node.routePreparation // {}) as $plan
            | {
                removeRoutes:
                  (($plan.removeRoutes // [])
                    + (($node.unsafeRoutes // [])
                      | map(select(.install // true) | .route))),
                overlayHosts:
                  (($plan.overlayHosts // []) + [$overlay4, $overlay6]),
                underlayEndpoints: [
                  $endpoint4,
                  $endpoint6,
                  $portForwardEndpoint4,
                  $portForwardEndpoint6
                ]
              }
            | with_entries(.value |= (map(select(. != null and . != "")) | unique))
          '
  )"
  lighthouse_static_host_map_yaml="$(
    if [ "$profile_context" != "remote" ] && [ "$external_suppress_public_lighthouse_static_map" = "1" ]; then
      if [ -n "$external_remote_lighthouse_endpoint4" ] || [ -n "$external_remote_lighthouse_endpoint6" ]; then
        printf '  "%s":\n' "$lighthouse_ip4"
        if [ -n "$external_remote_lighthouse_endpoint4" ]; then
          printf '    - "%s:%s"\n' "$external_remote_lighthouse_endpoint4" "$lighthouse_port"
        fi
        if [ -n "$external_remote_lighthouse_endpoint6" ]; then
          printf '    - "[%s]:%s"\n' "$external_remote_lighthouse_endpoint6" "$lighthouse_port"
        fi
        printf '  "%s":\n' "$lighthouse_ip6"
        if [ -n "$external_remote_lighthouse_endpoint4" ]; then
          printf '    - "%s:%s"\n' "$external_remote_lighthouse_endpoint4" "$lighthouse_port"
        fi
        if [ -n "$external_remote_lighthouse_endpoint6" ]; then
          printf '    - "[%s]:%s"\n' "$external_remote_lighthouse_endpoint6" "$lighthouse_port"
        fi
      fi
    else
      printf '  "%s":\n' "$lighthouse_ip4"
      if [ -n "$lighthouse_endpoint" ]; then
        printf '    - "%s:%s"\n' "$lighthouse_endpoint" "$lighthouse_port"
      fi
      if [ -n "$lighthouse_endpoint6" ]; then
        printf '    - "[%s]:%s"\n' "$lighthouse_endpoint6" "$lighthouse_port"
      fi
      printf '  "%s":\n' "$lighthouse_ip6"
      if [ -n "$lighthouse_endpoint" ]; then
        printf '    - "%s:%s"\n' "$lighthouse_endpoint" "$lighthouse_port"
      fi
      if [ -n "$lighthouse_endpoint6" ]; then
        printf '    - "[%s]:%s"\n' "$lighthouse_endpoint6" "$lighthouse_port"
      fi
    fi
  )"
  lighthouse_hosts_yaml="$(
    if
      [ "$profile_context" != "remote" ] \
      && [ "$external_suppress_public_lighthouse_static_map" = "1" ] \
      && [ -z "$external_remote_lighthouse_endpoint4" ] \
      && [ -z "$external_remote_lighthouse_endpoint6" ]
    then
      printf '  hosts: []\n'
    else
      printf '  hosts:\n'
      printf '    - "%s"\n' "$lighthouse_ip4"
      printf '    - "%s"\n' "$lighthouse_ip6"
    fi
  )"
  advertise_addrs_yaml="$(
    if printf '%s' "$external_port_forward_node_names_json" | jq -e --arg n "$profile_name" 'index($n) != null' >/dev/null; then
      advertised_endpoint4="$port_forward_endpoint"
      advertised_endpoint6="$port_forward_endpoint6"
      if [ "$advertised_endpoint4" = "$lighthouse_endpoint" ] && [ "$lighthouse_port" = "4242" ]; then
        advertised_endpoint4=""
      fi
      if [ "$advertised_endpoint6" = "$lighthouse_endpoint6" ] && [ "$lighthouse_port" = "4242" ]; then
        advertised_endpoint6=""
      fi
      if [ -z "$advertised_endpoint4" ] && [ -z "$advertised_endpoint6" ]; then
        echo "nebula-profile-bootstrap: ${profile_name} is marked public-forwarded but only has the lighthouse-owned public ${lighthouse_port} endpoint; model a unique public endpoint or remove the public-forwarded node" >&2
        exit 1
      fi
      if [ -n "$advertised_endpoint4" ] || [ -n "$advertised_endpoint6" ]; then
        printf '  advertise_addrs:\n'
        if [ -n "$advertised_endpoint4" ]; then
          printf '    - "%s:%s"\n' "$advertised_endpoint4" "$lighthouse_port"
        fi
        if [ -n "$advertised_endpoint6" ]; then
          printf '    - "[%s]:%s"\n' "$advertised_endpoint6" "$lighthouse_port"
        fi
      fi
    fi
  )"
  external_static_host_map_yaml="$(
    printf '%s' "$external_port_forward_node_names_json" \
      | jq -r '.[]' \
      | while read -r external_node_name; do
        [ -n "$external_node_name" ] || continue
        [ "$external_node_name" != "$profile_name" ] || continue
        if ! printf '%s' "$runtime_nodes_json" | jq -e --arg n "$external_node_name" 'has($n)' >/dev/null; then
          continue
        fi
        if ! printf '%s' "$runtime_nodes_json" | jq -e --arg n "$external_node_name" '.[$n].lighthouse.node == $n' >/dev/null; then
          continue
        fi
        external_node_port="$(
          printf '%s' "$runtime_nodes_json" \
            | jq -r --arg n "$external_node_name" '
                .[$n] as $node
                | if (($node.lighthouse.node // "") == $n) then
                    ($node.lighthouse.port // "4242")
                  else
                    "4242"
                  end
              '
        )"
        printf '%s' "$runtime_nodes_json" \
          | jq -r --arg n "$external_node_name" '[.[$n].certCidr4, .[$n].certCidr6] | .[]? | sub("/.*$"; "")' \
          | while read -r external_overlay_ip; do
            [ -n "$external_overlay_ip" ] || continue
            [ "$external_overlay_ip" != "$lighthouse_ip4" ] || continue
            [ "$external_overlay_ip" != "$lighthouse_ip6" ] || continue
            printf '  "%s":\n' "$external_overlay_ip"
            if [ -n "$port_forward_endpoint" ]; then
              printf '    - "%s:%s"\n' "$port_forward_endpoint" "$external_node_port"
            fi
            if [ -n "$port_forward_endpoint6" ]; then
              printf '    - "[%s]:%s"\n' "$port_forward_endpoint6" "$external_node_port"
            fi
          done
      done
  )"

  install -d -m 0700 "$profile_dir"
  install -m 0600 "$pki_dir/ca.crt" "$profile_dir/ca.crt"
  install -m 0600 "$pki_dir/$cert_name" "$profile_dir/$cert_name"
  install -m 0600 "$pki_dir/$key_name" "$profile_dir/$key_name"
  printf '%s\n' "$route_preparation_json" >"$profile_dir/route-preparation.json"
  if [ "$is_lighthouse" = "true" ]; then
    cat >"$profile_dir/config.yml" <<EOF
pki:
  ca: $pki_base/ca.crt
  cert: $pki_base/$cert_name
  key: $pki_base/$key_name
static_map:
  network: ip

static_host_map: {}

lighthouse:
  am_lighthouse: true

$relay_yaml

listen:
  host: "$listen_host"
  port: $lighthouse_port

tun:
  disabled: true
  dev: nebula1
  mtu: 1200
  drop_multicast: false
$(if [ -n "$unsafe_routes_yaml" ]; then cat <<UNSAFELH
  unsafe_routes:
$unsafe_routes_yaml
UNSAFELH
fi)

firewall:
  outbound:
    - port: any
      proto: any
      host: any
$(if [ -n "$unsafe_fw_rules" ]; then cat <<UNSAFEFWHO
$unsafe_fw_rules
UNSAFEFWHO
fi)
  inbound:
    - port: any
      proto: any
      host: any
$(if [ -n "$unsafe_fw_rules" ]; then cat <<UNSAFEFWHI
$unsafe_fw_rules
UNSAFEFWHI
fi)
EOF
  else
    cat >"$profile_dir/config.yml" <<EOF
pki:
  ca: $pki_base/ca.crt
  cert: $pki_base/$cert_name
  key: $pki_base/$key_name
static_map:
  network: ip

static_host_map:
$lighthouse_static_host_map_yaml
$(if [ -n "$external_static_host_map_yaml" ]; then printf '%s\n' "$external_static_host_map_yaml"; fi)

lighthouse:
  am_lighthouse: false
$lighthouse_hosts_yaml
  local_allow_list:
    '10.0.0.0/8': false
    '172.16.0.0/12': false
    '192.168.0.0/16': false
    '100.64.0.0/10': false
    '169.254.0.0/16': false
    'fc00::/7': false
    'fe80::/10': false
$advertise_addrs_yaml

punchy:
  punch: true

$relay_yaml

listen:
  host: "$listen_host"
  port: 4242

tun:
  dev: nebula1
  mtu: 1200
  drop_multicast: false
$(if [ -n "$unsafe_routes_yaml" ]; then cat <<UNSAFE
  unsafe_routes:
$unsafe_routes_yaml
UNSAFE
fi)

firewall:
  outbound:
    - port: any
      proto: any
      host: any
$(if [ -n "$unsafe_fw_rules" ]; then cat <<UNSAFEFWOUT
$unsafe_fw_rules
UNSAFEFWOUT
fi)
  inbound:
    - port: any
      proto: any
      host: any
$(if [ -n "$unsafe_fw_rules" ]; then cat <<UNSAFEFWIN
$unsafe_fw_rules
UNSAFEFWIN
fi)
EOF
  fi
}

printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
  install_profile "$node_name"
done

best_effort_restart_nebula_runtime() {
  local machine_name="$1"
  for _ in $(seq 1 10); do
    if machinectl show "$machine_name" --property Leader --value >/dev/null 2>&1; then
      if machinectl shell "$machine_name" /bin/sh -lc 'systemctl restart nebula-runtime' </dev/null >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  return 0
}

printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
  machine_name="$(
    printf '%s' "$runtime_nodes_json" \
      | jq -r --arg n "$node_name" '.[$n].materialization.container.targetContainer // $n'
  )"
  best_effort_restart_nebula_runtime "$machine_name"
done

remote_external_lighthouse_host=""
if [ -n "$external_lighthouse_ssh_host_secret" ] && [ -s "$external_lighthouse_ssh_host_secret" ]; then
  remote_external_lighthouse_host="$(tr -d '[:space:]' <"$external_lighthouse_ssh_host_secret")"
fi

ssh_remote_opts=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -i "$root_ssh_dir/id_ed25519"
)

if [ -n "$remote_external_lighthouse_host" ] && ssh \
  "${ssh_remote_opts[@]}" \
  "root@$remote_external_lighthouse_host" true 2>/dev/null; then
  remote_runtime_nodes="$(
    {
      printf '%s' "$external_runtime_node_names_json" | jq -r '.[]'
      printf '%s' "$external_runtime_node_names_json" \
        | jq -r --argjson nodes "$runtime_nodes_json" '
            .[]
            | select($nodes[.] != null)
            | $nodes[.].lighthouse.node
            | select(. != null and . != "")
          '
    } | sort -u
  )"

  printf '%s\n' "$remote_runtime_nodes" | while read -r node_name; do
    [ -n "$node_name" ] || continue
    if ! printf '%s' "$runtime_nodes_json" | jq -e --arg n "$node_name" 'has($n)' >/dev/null; then
      continue
    fi

    target_container="$(
      printf '%s' "$runtime_nodes_json" \
        | jq -r --arg n "$node_name" '.[$n].materialization.container.targetContainer // $n'
    )"
    remote_profile_dir="/persist/nebula-runtime/profiles/$node_name"
    install_profile "$node_name" remote

    scp -O -q "${ssh_remote_opts[@]}" \
      "$profiles_dir/$node_name/ca.crt" \
      "$profiles_dir/$node_name/$node_name.crt" \
      "$profiles_dir/$node_name/$node_name.key" \
      "$profiles_dir/$node_name/config.yml" \
      "$profiles_dir/$node_name/route-preparation.json" \
      "root@$remote_external_lighthouse_host:/root/" \
      </dev/null

    ssh "${ssh_remote_opts[@]}" "root@$remote_external_lighthouse_host" "
        set -euo pipefail
        node_name='$node_name'
        target_container='$target_container'
        remote_profile_dir='$remote_profile_dir'
        install -d -m 0700 \"\$remote_profile_dir\"
        install -m 0600 /root/ca.crt \"\$remote_profile_dir/ca.crt\"
        install -m 0600 /root/\$node_name.crt \"\$remote_profile_dir/\$node_name.crt\"
        install -m 0600 /root/\$node_name.key \"\$remote_profile_dir/\$node_name.key\"
        install -m 0600 /root/config.yml \"\$remote_profile_dir/config.yml\"
        install -m 0600 /root/route-preparation.json \"\$remote_profile_dir/route-preparation.json\"
        rm -f /root/ca.crt /root/\$node_name.crt /root/\$node_name.key /root/config.yml /root/route-preparation.json

        systemctl restart container@\$target_container.service
      " </dev/null
  done

  remote_lighthouse_base="/persist/nebula-runtime/lighthouses"

  printf '%s' "$lighthouses_json" | jq -r 'keys[]' | while read -r lighthouse_id; do
    if printf '%s' "$lighthouses_json" | jq -e --arg n "$lighthouse_id" '.[$n].internal == true' >/dev/null; then
      continue
    fi
    cert_base_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].certBaseName')"
    service_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].serviceName')"
    interface_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].interfaceName')"
    lighthouse_port="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].port')"
    unsafe_networks="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].unsafeNetworks | join(",")')"
    unsafe_networks="$(nebula_control_networks_csv "$unsafe_networks")"
    unsafe_gateway4=""
    unsafe_gateway6=""
    delegated_prefix=""
    hostile_overlay_id="$(
      printf '%s' "$runtime_nodes_json" \
        | jq -r '
            to_entries[]
            | select(
                any(.value.unsafeRoutes[]?; .route == "0.0.0.0/1" or .route == "128.0.0.0/1" or .route == "::/1" or .route == "8000::/1")
              )
            | .value.overlayId
          ' \
        | head -n1
    )"
    if [ -n "$hostile_overlay_id" ]; then
      unsafe_gateway4="$(
        printf '%s' "$runtime_nodes_json" \
          | jq -r --arg overlay "$hostile_overlay_id" '
              to_entries[]
              | select(.value.overlayId == $overlay)
              | select(any(.value.unsafeRoutes[]?; .route == "0.0.0.0/1" or .route == "128.0.0.0/1" or .route == "::/1" or .route == "8000::/1"))
              | .value.certCidr4
              | sub("/.*$"; "")
            ' \
          | head -n1
      )"
      unsafe_gateway6="$(
        printf '%s' "$runtime_nodes_json" \
          | jq -r --arg overlay "$hostile_overlay_id" '
              to_entries[]
              | select(.value.overlayId == $overlay)
              | select(any(.value.unsafeRoutes[]?; .route == "0.0.0.0/1" or .route == "128.0.0.0/1" or .route == "::/1" or .route == "8000::/1"))
              | .value.certCidr6
              | sub("/.*$"; "")
            ' \
          | head -n1
      )"
    fi
    delegated_prefixes=""
    ipv4_return_prefixes=""
    if [ -n "$hostile_overlay_id" ]; then
      lighthouse_overlay_ids_csv="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].overlayIds | join(",")')"
      if printf '%s\n' "$lighthouse_overlay_ids_csv" | tr ',' '\n' | grep -Fxq "$hostile_overlay_id"; then
        delegated_prefixes="$(access_prefixes_all)"
        while read -r delegated_prefix; do
          unsafe_networks="$(append_csv "$unsafe_networks" "$delegated_prefix")"
        done <<< "$delegated_prefixes"
        ipv4_return_prefixes="$(printf '%s\n' "$external_lighthouse_return_ipv4_cidrs_csv" | tr ',' '\n' | sed '/^$/d')"
        while read -r cidr; do
          unsafe_networks="$(append_csv "$unsafe_networks" "$cidr")"
        done <<< "$ipv4_return_prefixes"
      fi
    fi
    unsafe_routes_yaml=""
    if [ -n "$unsafe_networks" ] && { [ -n "$unsafe_gateway4" ] || [ -n "$unsafe_gateway6" ]; }; then
      while read -r cidr; do
        [ -n "$cidr" ] || continue
        {
          printf '%s\n' "$delegated_prefixes"
          printf '%s\n' "$ipv4_return_prefixes"
        } | grep -Fxq "$cidr" || continue
        if printf '%s' "$cidr" | grep -q ':'; then
          [ -n "$unsafe_gateway6" ] || continue
          via="$unsafe_gateway6"
        else
          [ -n "$unsafe_gateway4" ] || continue
          via="$unsafe_gateway4"
        fi

        route_yaml="    - route: $cidr
      via: $via
      mtu: 1280
      install: true"
        if [ -n "$unsafe_routes_yaml" ]; then
          unsafe_routes_yaml="$unsafe_routes_yaml
$route_yaml"
        else
          unsafe_routes_yaml="$route_yaml"
        fi
      done < <(printf '%s\n' "$unsafe_networks" | tr ',' '\n' | sed '/^$/d')
    fi
    unsafe_fw_rules="$(
      printf '%s\n' "$unsafe_networks" \
        | tr ',' '\n' \
        | sed '/^$/d' \
        | sed 's/^/    - port: any\
      proto: any\
      host: any\
      local_cidr: /'
    )"

    cat > "$profiles_dir/$cert_base_name.config.yml" <<EOF
pki:
  ca: $remote_lighthouse_base/$cert_base_name/ca.crt
  cert: $remote_lighthouse_base/$cert_base_name/$cert_base_name.crt
  key: $remote_lighthouse_base/$cert_base_name/$cert_base_name.key
static_map:
  network: ip

static_host_map: {}

lighthouse:
  am_lighthouse: true

listen:
  host: "[::]"
  port: $lighthouse_port

tun:
  disabled: true
  dev: $interface_name
  mtu: 1200
  drop_multicast: false
$(if [ -n "$unsafe_routes_yaml" ]; then cat <<UNSAFEREMOTE
  unsafe_routes:
$unsafe_routes_yaml
UNSAFEREMOTE
fi)

firewall:
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: any
      host: any
$(if [ -n "$unsafe_fw_rules" ]; then printf '%s\n' "$unsafe_fw_rules"; fi)
EOF

    scp -O -q "${ssh_remote_opts[@]}" \
      "$pki_dir/ca.crt" \
      "$pki_dir/$cert_base_name.crt" \
      "$pki_dir/$cert_base_name.key" \
      "$profiles_dir/$cert_base_name.config.yml" \
      "root@$remote_external_lighthouse_host:/root/" \
      </dev/null

    ssh "${ssh_remote_opts[@]}" "root@$remote_external_lighthouse_host" "
        set -euo pipefail
        remote_profile_dir='$remote_lighthouse_base/$cert_base_name'
        cert_base_name='$cert_base_name'
        service_name='$service_name'

        install -d -m 0700 \"\$remote_profile_dir\"
        install -m 0600 /root/ca.crt \"\$remote_profile_dir/ca.crt\"
        install -m 0600 /root/\$cert_base_name.crt \"\$remote_profile_dir/\$cert_base_name.crt\"
        install -m 0600 /root/\$cert_base_name.key \"\$remote_profile_dir/\$cert_base_name.key\"
        install -m 0600 /root/\$cert_base_name.config.yml \"\$remote_profile_dir/\$cert_base_name.config.yml\"
        rm -f /root/ca.crt /root/\$cert_base_name.crt /root/\$cert_base_name.key /root/\$cert_base_name.config.yml

        systemctl restart \$service_name.service
      " </dev/null
  done
else
  echo "nebula-profile-bootstrap: external lighthouse SSH key not authorized yet for root@$remote_external_lighthouse_host" >&2
fi
