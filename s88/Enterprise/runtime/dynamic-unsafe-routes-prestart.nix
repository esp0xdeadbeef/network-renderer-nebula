{ lib, pkgs, dynamicUnsafeRoutesJson, runtimeConfigPath }:

''
  install -d -m 0700 /run/nebula-runtime
  if [ ! -e ${runtimeConfigPath} ]; then
    install -m 0600 /etc/nebula/runtime.yml ${runtimeConfigPath}
  fi
  ${pkgs.python3}/bin/python3 - ${runtimeConfigPath} ${lib.escapeShellArg dynamicUnsafeRoutesJson} <<'PY'
  import ipaddress
  import json
  import pathlib
  import sys

  config_path = pathlib.Path(sys.argv[1])
  specs = json.loads(sys.argv[2])

  def read_prefix(spec):
      source_file = spec.get("sourceFile", "")
      raw = pathlib.Path(source_file).read_text(encoding="utf-8").strip()
      network = ipaddress.ip_network(raw, strict=False)
      return str(network)

  lines = config_path.read_text(encoding="utf-8").splitlines(True)
  cidrs = []
  routes = []
  for spec in specs:
      if not spec.get("sourceFile"):
          continue
      cidr = read_prefix(spec)
      cidrs.append(cidr)
      route = {"route": cidr, "mtu": 1280 if ":" in cidr else 1200, "install": True}
      via = spec.get("via6") or spec.get("via4") or spec.get("via")
      if via:
          route["via"] = via
      routes.append(route)

  if not routes:
      sys.exit(0)

  existing_cidrs = set()
  for line in lines:
      if line.lstrip().startswith("local_cidr: "):
          existing_cidrs.add(line.split("local_cidr: ", 1)[1].strip())

  def append_firewall_rule(section_name, cidr):
      marker = f"{section_name}:\n"
      for idx, line in enumerate(lines):
          if line == marker:
              lines[idx + 1:idx + 1] = [
                  "  - host: any\n",
                  f"    local_cidr: {cidr}\n",
                  "    port: any\n",
                  "    proto: any\n",
              ]
              return
      raise SystemExit(f"missing firewall section {section_name}")

  for cidr in sorted(set(cidrs) - existing_cidrs):
      append_firewall_rule("  inbound", cidr)
      append_firewall_rule("  outbound", cidr)

  route_keys = set()
  for line in lines:
      if line.lstrip().startswith("route: "):
          route_keys.add(line.split("route: ", 1)[1].strip())

  missing_routes = [route for route in routes if route["route"] not in route_keys]
  if missing_routes:
      for idx, line in enumerate(lines):
          if line.strip() == "unsafe_routes: []":
              lines[idx] = "  unsafe_routes:\n"
              insert_at = idx + 1
              break
          if line == "  unsafe_routes:\n":
              insert_at = idx + 1
              break
      else:
          for idx, line in enumerate(lines):
              if line == "tun:\n":
                  lines[idx + 1:idx + 1] = ["  unsafe_routes:\n"]
                  insert_at = idx + 2
                  break
          else:
              raise SystemExit("missing tun section")

      rendered = []
      for route in missing_routes:
          rendered.extend([
              "  - install: true\n",
              f"    mtu: {route['mtu']}\n",
              f"    route: {route['route']}\n",
          ])
          if route.get("via"):
              rendered.append(f"    via: {route['via']}\n")
      lines[insert_at:insert_at] = rendered

  config_path.write_text("".join(lines), encoding="utf-8")
  PY
''
