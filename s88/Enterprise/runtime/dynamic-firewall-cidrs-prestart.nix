{ lib, pkgs, dynamicFirewallCidrsJson, runtimeConfigPath }:

''
  install -d -m 0700 /run/nebula-runtime
  if [ ! -e ${runtimeConfigPath} ]; then
    install -m 0600 /etc/nebula/runtime.yml ${runtimeConfigPath}
  fi
  ${pkgs.python3}/bin/python3 - ${runtimeConfigPath} ${lib.escapeShellArg dynamicFirewallCidrsJson} <<'PY'
  import ipaddress
  import json
  import sys
  from pathlib import Path

  config_path = Path(sys.argv[1])
  specs = json.loads(sys.argv[2])

  def read_prefix(spec):
      source_file = spec.get("sourceFile", "")
      if not source_file:
          return ""
      value = Path(source_file).read_text(encoding="utf-8").strip()
      if not value:
          raise SystemExit(f"empty dynamic firewall CIDR source: {source_file}")
      return str(ipaddress.ip_network(value, strict=False))

  cidrs = sorted({read_prefix(spec) for spec in specs if spec.get("sourceFile", "")})
  cidrs = [cidr for cidr in cidrs if cidr]
  if not cidrs:
      raise SystemExit("no dynamic firewall CIDRs configured")

  lines = config_path.read_text(encoding="utf-8").splitlines(keepends=True)
  existing = set()
  for idx, line in enumerate(lines):
      if line.strip() == "local_cidr:" and idx + 1 < len(lines):
          existing.add(lines[idx + 1].strip())
      if line.lstrip().startswith("local_cidr: "):
          existing.add(line.split("local_cidr: ", 1)[1].strip())

  def rule_lines(cidr):
      return [
          "  - host: any\n",
          f"    local_cidr: {cidr}\n",
          "    port: any\n",
          "    proto: any\n",
      ]

  def insert_after(header, current_lines):
      result = []
      inserted = False
      for line in current_lines:
          result.append(line)
          if line == f"  {header}:\n":
              for cidr in cidrs:
                  if cidr not in existing:
                      result.extend(rule_lines(cidr))
              inserted = True
      if not inserted:
          raise SystemExit(f"firewall.{header} section not found in {config_path}")
      return result

  lines = insert_after("inbound", lines)
  lines = insert_after("outbound", lines)
  config_path.write_text("".join(lines), encoding="utf-8")
  PY
''
