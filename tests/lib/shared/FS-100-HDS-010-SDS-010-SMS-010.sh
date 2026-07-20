#!/usr/bin/env bash
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-050
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/cpm-bundle.json" <<'JSON'
{
  "nebulaRuntimePlan": {
    "meta": {
      "sourceClasses": {
        "userIntent": {
          "path": "examples/fs100/intent.nix",
          "narHash": "sha256-intent"
        },
        "publicInventory": {
          "path": "examples/fs100/inventory-nixos.nix",
          "narHash": "sha256-public-inventory"
        },
        "protectedInventory": {
          "ref": "sops://examples/fs100/protected.yaml",
          "secretValue": "PLAINTEXT-PROTECTED-VALUE"
        },
        "runtimeFacts": {
          "ref": "runtime://provider/public-addresses"
        },
        "validationContext": {
          "profile": "renderer-construction"
        }
      },
      "requested": {
        "scope": {
          "site": "nebula",
          "host": "s-router-nixos"
        },
        "target": {
          "renderer": "nebula",
          "role": "renderer-output"
        }
      },
      "locks": {
        "network-control-plane-model": {
          "rev": "1111222233334444555566667777888899990000",
          "narHash": "sha256-cpm"
        }
      },
      "controlledBaseline": "fs100-renderer-output-provenance"
    },
    "overlays": {
      "espbranch::site-b::east-west": {
        "enterpriseName": "espbranch",
        "siteName": "site-b",
        "name": "east-west",
        "lighthouse": {
          "overlayIps": ["100.96.10.254"],
          "endpoint": "198.51.100.10:4242"
        }
      }
    },
    "nodes": {
      "b-router-core-nebula": {
        "enterpriseName": "espbranch",
        "siteName": "site-b",
        "overlayName": "east-west",
        "overlayId": "espbranch::site-b::east-west",
        "overlayAddresses": ["100.96.10.2/24"],
        "groups": ["router"],
        "materialization": {
          "container": {
            "targetContainer": "b-router-core-nebula"
          }
        },
        "unsafeRoutes": [],
        "dynamicFirewallCidrs": [],
        "dynamicUnsafeRoutes": []
      }
    }
  }
}
JSON

nix build --no-link --no-warn-dirty --print-out-paths "${repo_root}#default" >"$tmp_dir/package-path"
runner="$(cat "$tmp_dir/package-path")/bin/network-renderer-nebula"

"$runner" render-node \
  --cpm "$tmp_dir/cpm-bundle.json" \
  --node b-router-core-nebula \
  --out "$tmp_dir/rendered"

if grep -F "PLAINTEXT-PROTECTED-VALUE" "$tmp_dir/rendered/runtime-node.json" >/dev/null; then
  echo "protected value leaked into Nebula provenance" >&2
  exit 1
fi

jq -e '
  .nodeName == "b-router-core-nebula" and
  .provenance.renderer.repository == "network-renderer-nebula" and
  (.provenance.renderer.gitRev | type == "string") and
  .provenance.renderer.schemaVersion == 2 and
  .provenance.input.kind == "nebula-runtime-plan" and
  .provenance.output.kind == "nebula-runtime-node" and
  .provenance.output.artifact == "'"$tmp_dir"'/rendered/runtime-node.json" and
  .provenance.output.nodeName == "b-router-core-nebula" and
  .provenance.sources.sourceClasses.userIntent.path == "examples/fs100/intent.nix" and
  .provenance.sources.sourceClasses.publicInventory.path == "examples/fs100/inventory-nixos.nix" and
  .provenance.sources.sourceClasses.protectedInventory.secretValue == "<redacted>" and
  .provenance.sources.sourceClasses.runtimeFacts.ref == "runtime://provider/public-addresses" and
  .provenance.sources.sourceClasses.validationContext.profile == "renderer-construction" and
  (.provenance.sources.missingSourceClasses | length) == 0 and
  .provenance.requested.scope.site == "nebula" and
  .provenance.requested.target.renderer == "nebula" and
  .provenance.requested.derivedScope.nodeName == "b-router-core-nebula" and
  .provenance.requested.derivedScope.overlayId == "espbranch::site-b::east-west" and
  .provenance.locks.upstream["network-control-plane-model"].rev == "1111222233334444555566667777888899990000" and
  .provenance.locks.renderer.available == true and
  .provenance.controlledBaseline == "fs100-renderer-output-provenance"
' "$tmp_dir/rendered/runtime-node.json" >/dev/null

jq 'del(.nebulaRuntimePlan.meta.sourceClasses.runtimeFacts, .nebulaRuntimePlan.meta.sourceClasses.validationContext)' \
  "$tmp_dir/cpm-bundle.json" >"$tmp_dir/cpm-missing-optional.json"

"$runner" render-node \
  --cpm "$tmp_dir/cpm-missing-optional.json" \
  --node b-router-core-nebula \
  >"$tmp_dir/stdout-runtime-node.json"

jq -e '
  .provenance.output.artifact == "stdout" and
  (.provenance.sources.missingSourceClasses | index("runtimeFacts:not-declared") != null) and
  (.provenance.sources.missingSourceClasses | index("validationContext:not-declared") != null)
' "$tmp_dir/stdout-runtime-node.json" >/dev/null

echo "PASS fs100-renderer-output-provenance"
