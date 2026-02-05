#!/usr/bin/env bash
set -Eeuo pipefail

# Generate GitHub labels and labeler rules from kubernetes/apps directory structure
# This script auto-generates area/ labels for namespaces and apps

ROOT_DIR="$(git rev-parse --show-toplevel)"
APPS_DIR="${ROOT_DIR}/kubernetes/apps"
LABELS_FILE="${ROOT_DIR}/.github/labels.yaml"
LABELER_FILE="${ROOT_DIR}/.github/labeler.yaml"

# Color definitions
COLOR_AREA_GENERAL="0e8a16"    # Green - general areas
COLOR_AREA_NAMESPACE="1d76db"  # Blue - kubernetes namespaces
COLOR_AREA_APP="6f42c1"        # Purple - individual apps
COLOR_COMPONENT="5319e7"       # Dark purple - components
COLOR_TYPE_BUG="d73a4a"
COLOR_TYPE_FEATURE="a2eeef"
COLOR_TYPE_ENHANCEMENT="84b6eb"
COLOR_TYPE_REFACTOR="fbca04"
COLOR_TYPE_CHORE="fef2c0"
COLOR_TYPE_CI="ededed"
COLOR_TYPE_SECURITY="b60205"
COLOR_TYPE_BREAKING="d93f0b"
COLOR_TYPE_DOCS="0075ca"
COLOR_TYPE_DIGEST="ffeC19"
COLOR_TYPE_PATCH="ffeC19"
COLOR_TYPE_MINOR="ff9800"
COLOR_TYPE_MAJOR="f6412d"
COLOR_RENOVATE="027fa0"
COLOR_PRIORITY_CRITICAL="b60205"
COLOR_PRIORITY_HIGH="d93f0b"
COLOR_PRIORITY_MEDIUM="fbca04"
COLOR_PRIORITY_LOW="0e8a16"
COLOR_STATUS_REVIEW="d4c5f9"
COLOR_STATUS_BLOCKED="d73a4a"
COLOR_STATUS_WIP="fbca04"
COLOR_STATUS_READY="0e8a16"
COLOR_SIZE_XS="c2e0c6"
COLOR_SIZE_S="a8d9ae"
COLOR_SIZE_M="7ec984"
COLOR_SIZE_L="60b86b"
COLOR_SIZE_XL="3f8c4f"
COLOR_SPECIAL_COMMUNITY="370fb2"
COLOR_SPECIAL_HOLD="ee0701"
COLOR_SPECIAL_FIRST="7057ff"
COLOR_SPECIAL_HELP="008672"
COLOR_SPECIAL_DEPS="0366d6"

generate_labels() {
    cat <<'EOF'
---
# Auto-generated labels - DO NOT EDIT MANUALLY
# Run: ./scripts/generate-labels.sh to regenerate
# Manual labels are preserved in the static sections below

# Area Labels - General (static)
- name: area/bootstrap
  color: "0e8a16"
  description: "Changes to bootstrap configuration"
- name: area/docs
  color: "0e8a16"
  description: "Documentation updates"
- name: area/github
  color: "0e8a16"
  description: "GitHub workflows and configuration"
- name: area/kubernetes
  color: "0e8a16"
  description: "Kubernetes manifests and configuration"
- name: area/mise
  color: "0e8a16"
  description: "Development tooling configuration"
- name: area/renovate
  color: "0e8a16"
  description: "Renovate dependency updates"
- name: area/scripts
  color: "0e8a16"
  description: "Shell scripts and automation"
- name: area/talos
  color: "0e8a16"
  description: "Talos Linux configuration"
- name: area/templates
  color: "0e8a16"
  description: "Jinja2 template changes"
- name: area/taskfile
  color: "0e8a16"
  description: "Task automation definitions"

# Area Labels - Kubernetes Namespaces (auto-generated)
EOF

    # Generate namespace labels
    for ns_dir in "${APPS_DIR}"/*/; do
        ns=$(basename "$ns_dir")
        [[ -d "$ns_dir" ]] || continue
        echo "- name: area/${ns}"
        echo "  color: \"${COLOR_AREA_NAMESPACE}\""
        echo "  description: \"${ns} namespace\""
    done

    cat <<'EOF'

# Area Labels - Kubernetes Apps (auto-generated)
EOF

    # Generate app labels
    for ns_dir in "${APPS_DIR}"/*/; do
        ns=$(basename "$ns_dir")
        [[ -d "$ns_dir" ]] || continue
        for app_dir in "${ns_dir}"/*/; do
            [[ -d "$app_dir" ]] || continue
            app=$(basename "$app_dir")
            echo "- name: app/${app}"
            echo "  color: \"${COLOR_AREA_APP}\""
            echo "  description: \"${app} in ${ns}\""
        done
    done

    cat <<EOF

# Component Labels (static)
- name: component/cilium
  color: "${COLOR_COMPONENT}"
  description: "Cilium CNI networking"
- name: component/flux
  color: "${COLOR_COMPONENT}"
  description: "Flux CD GitOps"
- name: component/envoy
  color: "${COLOR_COMPONENT}"
  description: "Envoy Gateway ingress"
- name: component/coredns
  color: "${COLOR_COMPONENT}"
  description: "CoreDNS configuration"
- name: component/cert-manager
  color: "${COLOR_COMPONENT}"
  description: "cert-manager TLS"
- name: component/external-dns
  color: "${COLOR_COMPONENT}"
  description: "External DNS management"
- name: component/sops
  color: "${COLOR_COMPONENT}"
  description: "SOPS secrets encryption"
- name: component/prometheus
  color: "${COLOR_COMPONENT}"
  description: "Prometheus monitoring"
- name: component/grafana
  color: "${COLOR_COMPONENT}"
  description: "Grafana dashboards"
- name: component/volsync
  color: "${COLOR_COMPONENT}"
  description: "Volsync backup system"
- name: component/kubevirt
  color: "${COLOR_COMPONENT}"
  description: "KubeVirt core and CDI"
- name: component/kubevirt-vms
  color: "${COLOR_COMPONENT}"
  description: "KubeVirt virtual machines"
- name: component/spegel
  color: "${COLOR_COMPONENT}"
  description: "Spegel peer-to-peer image sharing"

# Type Labels - Development (static)
- name: type/bug
  color: "${COLOR_TYPE_BUG}"
  description: "Bug fix"
- name: type/feature
  color: "${COLOR_TYPE_FEATURE}"
  description: "New feature"
- name: type/enhancement
  color: "${COLOR_TYPE_ENHANCEMENT}"
  description: "Enhancement to existing feature"
- name: type/refactor
  color: "${COLOR_TYPE_REFACTOR}"
  description: "Code refactoring"
- name: type/chore
  color: "${COLOR_TYPE_CHORE}"
  description: "Maintenance and chores"
- name: type/ci
  color: "${COLOR_TYPE_CI}"
  description: "CI/CD changes"
- name: type/security
  color: "${COLOR_TYPE_SECURITY}"
  description: "Security improvements"
- name: type/breaking
  color: "${COLOR_TYPE_BREAKING}"
  description: "Breaking change"
- name: type/docs
  color: "${COLOR_TYPE_DOCS}"
  description: "Documentation only"

# Type Labels - Renovate Semantic (static)
- name: type/digest
  color: "${COLOR_TYPE_DIGEST}"
  description: "Digest update"
- name: type/patch
  color: "${COLOR_TYPE_PATCH}"
  description: "Patch version update"
- name: type/minor
  color: "${COLOR_TYPE_MINOR}"
  description: "Minor version update"
- name: type/major
  color: "${COLOR_TYPE_MAJOR}"
  description: "Major version update"

# Renovate Source Types (static)
- name: renovate/container
  color: "${COLOR_RENOVATE}"
  description: "Container image update"
- name: renovate/github-action
  color: "${COLOR_RENOVATE}"
  description: "GitHub Action update"
- name: renovate/grafana-dashboard
  color: "${COLOR_RENOVATE}"
  description: "Grafana dashboard update"
- name: renovate/github-release
  color: "${COLOR_RENOVATE}"
  description: "GitHub release update"
- name: renovate/helm
  color: "${COLOR_RENOVATE}"
  description: "Helm chart update"

# Priority Labels (static)
- name: priority/critical
  color: "${COLOR_PRIORITY_CRITICAL}"
  description: "Critical priority"
- name: priority/high
  color: "${COLOR_PRIORITY_HIGH}"
  description: "High priority"
- name: priority/medium
  color: "${COLOR_PRIORITY_MEDIUM}"
  description: "Medium priority"
- name: priority/low
  color: "${COLOR_PRIORITY_LOW}"
  description: "Low priority"

# Status Labels (static)
- name: status/needs-review
  color: "${COLOR_STATUS_REVIEW}"
  description: "Needs code review"
- name: status/needs-testing
  color: "${COLOR_STATUS_REVIEW}"
  description: "Needs testing"
- name: status/blocked
  color: "${COLOR_STATUS_BLOCKED}"
  description: "Blocked by dependencies"
- name: status/wip
  color: "${COLOR_STATUS_WIP}"
  description: "Work in progress"
- name: status/ready
  color: "${COLOR_STATUS_READY}"
  description: "Ready to merge"

# Size Labels (static)
- name: size/xs
  color: "${COLOR_SIZE_XS}"
  description: "Extra small change (1-9 lines)"
- name: size/s
  color: "${COLOR_SIZE_S}"
  description: "Small change (10-29 lines)"
- name: size/m
  color: "${COLOR_SIZE_M}"
  description: "Medium change (30-99 lines)"
- name: size/l
  color: "${COLOR_SIZE_L}"
  description: "Large change (100-499 lines)"
- name: size/xl
  color: "${COLOR_SIZE_XL}"
  description: "Extra large change (500+ lines)"

# Special Labels (static)
- name: community
  color: "${COLOR_SPECIAL_COMMUNITY}"
  description: "Community contribution"
- name: hold
  color: "${COLOR_SPECIAL_HOLD}"
  description: "Do not merge"
- name: good-first-issue
  color: "${COLOR_SPECIAL_FIRST}"
  description: "Good for newcomers"
- name: help-wanted
  color: "${COLOR_SPECIAL_HELP}"
  description: "Help wanted"
- name: dependencies
  color: "${COLOR_SPECIAL_DEPS}"
  description: "Dependency updates"
EOF
}

generate_labeler() {
    cat <<'EOF'
---
# Auto-generated labeler rules - DO NOT EDIT MANUALLY
# Run: ./scripts/generate-labels.sh to regenerate

# Area Labels - General
area/bootstrap:
  - changed-files:
      - any-glob-to-any-file:
          - bootstrap/**/*

area/docs:
  - changed-files:
      - any-glob-to-any-file:
          - "*.md"
          - docs/**/*
          - CLAUDE.md

area/github:
  - changed-files:
      - any-glob-to-any-file:
          - .github/**/*

area/kubernetes:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/**/*

area/mise:
  - changed-files:
      - any-glob-to-any-file:
          - .mise.toml

area/renovate:
  - changed-files:
      - any-glob-to-any-file:
          - .renovate/**/*
          - .renovaterc.json5

area/scripts:
  - changed-files:
      - any-glob-to-any-file:
          - scripts/**/*

area/talos:
  - changed-files:
      - any-glob-to-any-file:
          - talos/**/*

area/taskfile:
  - changed-files:
      - any-glob-to-any-file:
          - .taskfiles/**/*
          - Taskfile.yaml

area/templates:
  - changed-files:
      - any-glob-to-any-file:
          - templates/**/*
          - makejinja.toml

# Area Labels - Kubernetes Namespaces (auto-generated)
EOF

    # Generate namespace labeler rules
    for ns_dir in "${APPS_DIR}"/*/; do
        ns=$(basename "$ns_dir")
        [[ -d "$ns_dir" ]] || continue
        cat <<EOF
area/${ns}:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/${ns}/**/*

EOF
    done

    cat <<'EOF'
# App Labels - Kubernetes Apps (auto-generated)
EOF

    # Generate app labeler rules
    for ns_dir in "${APPS_DIR}"/*/; do
        ns=$(basename "$ns_dir")
        [[ -d "$ns_dir" ]] || continue
        for app_dir in "${ns_dir}"/*/; do
            [[ -d "$app_dir" ]] || continue
            app=$(basename "$app_dir")
            cat <<EOF
app/${app}:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/${ns}/${app}/**/*

EOF
        done
    done

    cat <<'EOF'
# Component Labels (static)
component/cilium:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/kube-system/cilium/**/*

component/flux:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/flux-system/**/*
          - kubernetes/flux/**/*

component/envoy:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/network/envoy-gateway/**/*

component/coredns:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/kube-system/coredns/**/*

component/cert-manager:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/cert-manager/**/*

component/external-dns:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/network/k8s-gateway/**/*
          - kubernetes/apps/network/cloudflare-dns/**/*

component/sops:
  - changed-files:
      - any-glob-to-any-file:
          - "**/*.sops.yaml"
          - "**/*.sops.yml"
          - .sops.yaml
          - kubernetes/components/sops/**/*

component/prometheus:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/observability/kube-prometheus-stack/**/*
          - kubernetes/apps/observability/blackbox-exporter/**/*
          - kubernetes/components/alerts/**/*

component/grafana:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/observability/grafana/**/*

component/volsync:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/volsync-system/volsync/**/*
          - kubernetes/components/volsync/**/*

component/kubevirt:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/kubevirt/kubevirt/**/*
          - kubernetes/apps/kubevirt/cdi/**/*

component/kubevirt-vms:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/kubevirt/virtualmachines/**/*

component/spegel:
  - changed-files:
      - any-glob-to-any-file:
          - kubernetes/apps/kube-system/spegel/**/*

# Type Labels - Based on file patterns
type/ci:
  - changed-files:
      - any-glob-to-any-file:
          - .github/workflows/**/*
          - .github/actions/**/*

type/docs:
  - changed-files:
      - any-glob-to-any-file:
          - "*.md"
          - docs/**/*
      - all-globs-to-all-files:
          - "!**/*.{yaml,yml,sh,py,toml,json}"

type/security:
  - changed-files:
      - any-glob-to-any-file:
          - "**/*.sops.yaml"
          - "**/*.sops.yml"
          - .sops.yaml
          - kubernetes/apps/external-secrets/**/*

dependencies:
  - changed-files:
      - any-glob-to-any-file:
          - .mise.toml
          - bootstrap/helmfile.d/**/*
EOF
}

echo "Generating labels.yaml..."
generate_labels > "$LABELS_FILE"

echo "Generating labeler.yaml..."
generate_labeler > "$LABELER_FILE"

echo "Done! Generated:"
echo "  - ${LABELS_FILE}"
echo "  - ${LABELER_FILE}"
