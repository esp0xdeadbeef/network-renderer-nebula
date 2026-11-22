#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
set -euo pipefail

# One route authority, one next-hop set — asserted on this renderer's plan.
#
# URS, "Canonical Realization and Renderer Boundary": "A platform binding may
# bind canonical objects to target mechanics, but shall not create or duplicate
# topology, policy, reachability, addressing, routing ...".
#
# FS-310-HDS-020-SDS-010-SMS-060: "One route-selection authority shall have one
# modeled semantic next-hop set. Different next-hop sets for the same authority
# shall fail unless explicit multipath policy names the complete authorized
# member set." Its Construction Handoff names this renderer class explicitly:
# "network-renderer-nixos and the CLAB renderer shall consume the same canonical
# records and emit equivalent route cardinality and failure behavior."
#
# Here an authority is (node, destination prefix). Nebula carries routes as
# `unsafe_routes`, each with a `route` and a `via`; two entries for one prefix
# with different `via` values is one authority with two next hops, which this
# renderer must reject rather than emit.
#
# Harness guards (a broken comparison must not masquerade as a finding):
#   * the plan must yield routes at all;
#   * the route field must be populated, so the comparison has something to
#     compare rather than silently matching empty strings.

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
trace_id="FS-310-HDS-020-SDS-010-SMS-060"

out="$(mktemp)"
trap 'rm -f "${out}"' EXIT

REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    system = builtins.currentSystem;
    renderer = flake.libBySystem.${system}.renderer;
    labs = flake.inputs.network-labs.outPath;
    example = labs + "/examples/s-router-public-overlay-service";
    cpm = flake.inputs.network-control-plane-model.libBySystem.${system}.compileAndBuildFromPaths {
      inputPath = example + "/intent.nix";
      inventoryPath = example + "/inventory-nixos.nix";
    };
    plan = renderer.buildNebulaPlan {
      controlPlane = cpm;
      cpmData = cpm.control_plane_model.data;
    };

    routes = builtins.concatLists (map
      (nodeName:
        map
          (r: {
            node = nodeName;
            route = r.route or "";
            via = if (r.via or null) != null then r.via
                  else if (r.via4 or null) != null then r.via4
                  else if (r.via6 or null) != null then r.via6
                  else null;
          })
          (plan.nodes.${nodeName}.unsafeRoutes or [ ]))
      (builtins.attrNames (plan.nodes or { })));

    structured = builtins.filter (r: r.route != "") routes;
    grouped = builtins.groupBy (r: "${r.node}|${r.route}") structured;
    duplicates = map
      (k:
        let group = grouped.${k};
            vias = builtins.filter (v: v != null) (map (r: r.via) group);
        in "${k}  vias: ${builtins.concatStringsSep ", " (builtins.attrNames (builtins.groupBy (v: v) vias))}")
      (builtins.filter
        (k:
          let group = grouped.${k};
              vias = builtins.filter (v: v != null) (map (r: r.via) group);
          in (builtins.length (builtins.attrNames (builtins.groupBy (v: v) vias))) > 1)
        (builtins.attrNames grouped));
  in {
    routeCount = builtins.length routes;
    structuredCount = builtins.length structured;
    withVia = builtins.length (builtins.filter (r: r.via != null) structured);
    inherit duplicates;
  }
' >"${out}"

route_count="$(jq -r '.routeCount' "${out}")"
structured_count="$(jq -r '.structuredCount' "${out}")"
with_via="$(jq -r '.withVia' "${out}")"

if [[ "${route_count}" == "0" ]]; then
  printf 'FAIL %s: harness error -- the plan yielded no unsafe routes, so the clause is vacuous here\n' "${trace_id}" >&2
  exit 1
fi
if [[ "${structured_count}" == "0" ]]; then
  printf 'FAIL %s: harness error -- unsafe routes carry no `route` field, so destinations cannot be compared\n' "${trace_id}" >&2
  exit 1
fi
if [[ "${with_via}" == "0" ]]; then
  printf 'FAIL %s: harness error -- no unsafe route carries a via, so next-hop sets cannot be compared\n' "${trace_id}" >&2
  exit 1
fi

if [[ "$(jq -r '.duplicates | length' "${out}")" != "0" ]]; then
  printf 'FAIL %s: one route authority carries more than one next hop\n' "${trace_id}" >&2
  jq -r '.duplicates[] | "  \(.)"' "${out}" >&2
  printf '  SMS-060: different next-hop sets for the same authority shall fail unless explicit multipath names the member set.\n' >&2
  exit 1
fi

printf 'PASS %s (%s unsafe route(s), %s with a via, every (node, prefix) has one next-hop set)\n' \
  "${trace_id}" "${structured_count}" "${with_via}"
