{
  lib,
  pkgs,
  networkName,
  runtimeConfigPath,
  externalRemoteLighthouseEndpoint4SecretPath,
  externalRemoteLighthouseEndpoint6SecretPath,
  listenPort,
  lighthouseIp4,
  lighthouseIp6,
  staticHostMapSecretEndpointsJson,
}:

let
  secretPathOrEmpty = path: if path == null then "" else path;
in
''
  set -eu
  install -d -m 0700 /run/nebula-runtime
  install -m 0600 /etc/nebula/${networkName}.yml ${runtimeConfigPath}
  ${pkgs.python3}/bin/python3 - ${runtimeConfigPath} ${lib.escapeShellArg (secretPathOrEmpty externalRemoteLighthouseEndpoint4SecretPath)} ${lib.escapeShellArg (secretPathOrEmpty externalRemoteLighthouseEndpoint6SecretPath)} ${toString listenPort} ${lib.escapeShellArg lighthouseIp4} ${lib.escapeShellArg lighthouseIp6} ${lib.escapeShellArg staticHostMapSecretEndpointsJson} <<'PY'
  import sys
  import ipaddress
  import json
  from pathlib import Path

  config_path = Path(sys.argv[1])
  endpoint4_path = sys.argv[2]
  endpoint6_path = sys.argv[3]
  port = sys.argv[4]
  lighthouse_ip4 = sys.argv[5]
  lighthouse_ip6 = sys.argv[6]
  secret_endpoint_specs = json.loads(sys.argv[7])

  def read_endpoint(path):
      if not path:
          return ""
      value = Path(path).read_text(encoding="utf-8").strip()
      if not value:
          raise SystemExit(f"empty lighthouse endpoint secret: {path}")
      if "/" in value:
          network = ipaddress.ip_network(value, strict=False)
          if network.prefixlen < network.max_prefixlen:
              return str(network.network_address + 1)
          return str(network.network_address)
      return value.split("/", 1)[0]

  def format_endpoint(value, endpoint_port):
      if ":" in value:
          return f"'[{value}]:{endpoint_port}'"
      return f"{value}:{endpoint_port}"

  replacements = {}
  endpoint4 = read_endpoint(endpoint4_path)
  endpoint6 = read_endpoint(endpoint6_path)
  endpoints = []
  if endpoint4:
      endpoints.append(format_endpoint(endpoint4, port))
  if endpoint6:
      endpoints.append(format_endpoint(endpoint6, port))
  if endpoints:
      replacements[lighthouse_ip4] = endpoints
      replacements[lighthouse_ip6] = endpoints

  for overlay_ip, specs in secret_endpoint_specs.items():
      spec_endpoints = []
      for spec in specs:
          source_path = spec.get("sourceFile", "")
          endpoint_port = str(spec.get("port", port))
          endpoint = read_endpoint(source_path)
          if endpoint:
              spec_endpoints.append(format_endpoint(endpoint, endpoint_port))
      if spec_endpoints:
          replacements[overlay_ip] = spec_endpoints

  if not replacements:
      raise SystemExit("no dynamic static_host_map replacements configured")

  lines = config_path.read_text(encoding="utf-8").splitlines(keepends=True)
  updated = []
  in_static_map = False
  replaced_keys = set()
  skip_key = False

  for line in lines:
      if line == "static_host_map:\n":
          in_static_map = True
          updated.append(line)
          continue
      if in_static_map and line and not line.startswith(" "):
          in_static_map = False
          skip_key = False
          updated.append(line)
          continue
      if in_static_map and line.startswith("  ") and line.endswith(":\n") and not line.startswith("  - "):
          key = line[2:-2]
          updated.append(line)
          if key in replacements:
              updated.extend(f"  - {endpoint}\n" for endpoint in replacements[key])
              replaced_keys.add(key)
              skip_key = True
          else:
              skip_key = False
          continue
      if in_static_map and skip_key and line.startswith("  - "):
          continue
      updated.append(line)

  missing = sorted(set(replacements) - replaced_keys)
  if missing:
      raise SystemExit(f"static_host_map had no entries to replace for: {', '.join(missing)}")
  config_path.write_text("".join(updated), encoding="utf-8")
  PY
''
