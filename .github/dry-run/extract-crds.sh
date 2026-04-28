#!/usr/bin/env bash
# Extracts CRDs from every chart referenced by kubernetes/apps/ so the
# dry-run workflow can validate manifests against a complete schema set
# without maintaining a duplicate chart list. Discovers:
#   - OCIRepository (Flux v2 OCI source)
#   - HelmRelease + HelmRepository (Flux v2 HTTP/HTTPS chart source)
# For each unique chart it runs `helm template --include-crds` and emits
# only resources of kind CustomResourceDefinition on stdout.

set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
APPS_DIR="${REPO_ROOT}/kubernetes/apps"

OCI_LIST="$(mktemp)"
HELM_REPOS="$(mktemp)"
HELM_RELEASES="$(mktemp)"
trap 'rm -f "$OCI_LIST" "$HELM_REPOS" "$HELM_RELEASES"' EXIT

log() { printf '%s\n' "$*" >&2; }

# OCIRepository: url<TAB>tag (deduped, names irrelevant for CRD extraction)
find "$APPS_DIR" -name "*.yaml" -type f -print0 \
  | xargs -0 -I{} yq eval-all '
      select(.kind == "OCIRepository")
      | [.spec.url, .spec.ref.tag] | @tsv
    ' {} 2>/dev/null \
  | awk -F'\t' 'NF == 2 && $1 != "" && $2 != ""' \
  | sort -u > "$OCI_LIST"

# HelmRepository: namespace<TAB>name<TAB>url
find "$APPS_DIR" -name "*.yaml" -type f -print0 \
  | xargs -0 -I{} yq eval-all '
      select(.kind == "HelmRepository")
      | [.metadata.namespace // "flux-system", .metadata.name, .spec.url] | @tsv
    ' {} 2>/dev/null \
  | awk -F'\t' 'NF == 3 && $2 != "" && $3 != ""' \
  | sort -u > "$HELM_REPOS"

# HelmRelease (HelmRepository source): chart<TAB>version<TAB>repo-ns<TAB>repo-name (deduped)
find "$APPS_DIR" -name "*.yaml" -type f -print0 \
  | xargs -0 -I{} yq eval-all '
      select(.kind == "HelmRelease" and .spec.chart.spec.sourceRef.kind == "HelmRepository")
      | [
          .spec.chart.spec.chart,
          .spec.chart.spec.version,
          .spec.chart.spec.sourceRef.namespace // .metadata.namespace // "flux-system",
          .spec.chart.spec.sourceRef.name
        ] | @tsv
    ' {} 2>/dev/null \
  | awk -F'\t' 'NF == 4 && $1 != "" && $2 != ""' \
  | sort -u > "$HELM_RELEASES"

log "Discovered $(wc -l < "$OCI_LIST") OCI charts, $(wc -l < "$HELM_REPOS") helm repos, $(wc -l < "$HELM_RELEASES") helm releases"

render() {
  local label="$1"; shift
  local rendered err
  err=$(mktemp)
  if rendered=$(helm template "$@" --include-crds --no-hooks 2>"$err"); then
    printf '%s\n' "$rendered" \
      | yq eval-all 'select(.kind == "CustomResourceDefinition")' -
  else
    log "[warn] $label failed: $(head -1 "$err")"
  fi
  rm -f "$err"
}

# OCI charts
while IFS=$'\t' read -r url tag; do
  log "[oci] $url $tag"
  render "oci/$url@$tag" crds "$url" --version "$tag"
done < "$OCI_LIST"

# HelmRepository-backed charts
while IFS=$'\t' read -r chart version repo_ns repo_name; do
  url=$(awk -F'\t' -v ns="$repo_ns" -v n="$repo_name" '$1 == ns && $2 == n { print $3; exit }' "$HELM_REPOS")
  if [[ -z "$url" ]]; then
    log "[skip] $chart: HelmRepository $repo_ns/$repo_name not found"
    continue
  fi
  log "[hr]  $chart $version $url"
  render "hr/$chart@$version" crds "$chart" --repo "$url" --version "$version"
done < "$HELM_RELEASES"
