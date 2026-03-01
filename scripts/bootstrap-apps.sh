#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
export ROOT_DIR="$(git rev-parse --show-toplevel)"

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
    log debug "Waiting for nodes to be available"

    # Skip waiting if all nodes are 'Ready=True'
    if kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        log info "Nodes are available and ready, skipping wait for nodes"
        return
    fi

    # Wait for all nodes to be 'Ready=False'
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        log info "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
        sleep 10
    done
}

# Namespaces to be applied before the SOPS secrets are installed
function apply_namespaces() {
    log debug "Applying namespaces"

    local -r apps_dir="${ROOT_DIR}/kubernetes/apps"

    if [[ ! -d "${apps_dir}" ]]; then
        log error "Directory does not exist" "directory=${apps_dir}"
    fi

    for app in "${apps_dir}"/*/; do
        namespace=$(basename "${app}")

        # Check if the namespace resources are up-to-date
        if kubectl get namespace "${namespace}" &>/dev/null; then
            log info "Namespace resource is up-to-date" "resource=${namespace}"
            continue
        fi

        # Apply the namespace resources
        if kubectl create namespace "${namespace}" --dry-run=client --output=yaml \
            | kubectl apply --server-side --filename - &>/dev/null;
        then
            log info "Namespace resource applied" "resource=${namespace}"
        else
            log error "Failed to apply namespace resource" "resource=${namespace}"
        fi
    done
}

# Bootstrap secrets required before Flux and ESO are running
# - sops-age: Age key for SOPS decryption (needed by kustomize-controller)
# - onepassword-secret: 1Password service account token (needed by ESO)
# - github-deploy-key: Fetched from 1Password via op CLI
# All other secrets are managed by External Secrets Operator via 1Password
function apply_bootstrap_secrets() {
    log debug "Applying bootstrap secrets"

    # Apply sops-age secret (still needed for onepassword-secret decryption)
    local -r sops_age_secret="${ROOT_DIR}/bootstrap/sops-age.sops.yaml"
    if [ -f "${sops_age_secret}" ]; then
        if sops exec-file "${sops_age_secret}" "kubectl --namespace flux-system diff --filename {}" &>/dev/null; then
            log info "Secret resource is up-to-date" "resource=sops-age"
        elif sops exec-file "${sops_age_secret}" "kubectl --namespace flux-system apply --server-side --filename {}" &>/dev/null; then
            log info "Secret resource applied successfully" "resource=sops-age"
        else
            log error "Failed to apply secret resource" "resource=sops-age"
        fi
    else
        log warn "File does not exist" "file=${sops_age_secret}"
    fi

    # Apply onepassword secret (needed for ESO ClusterSecretStore)
    local -r onepassword_secret="${ROOT_DIR}/bootstrap/onepassword-secret.sops.yaml"
    if [ -f "${onepassword_secret}" ]; then
        if sops exec-file "${onepassword_secret}" "kubectl diff --filename {}" &>/dev/null; then
            log info "Secret resource is up-to-date" "resource=onepassword-secret"
        elif sops exec-file "${onepassword_secret}" "kubectl apply --server-side --filename {}" &>/dev/null; then
            log info "Secret resource applied successfully" "resource=onepassword-secret"
        else
            log error "Failed to apply secret resource" "resource=onepassword-secret"
        fi
    else
        log warn "File does not exist" "file=${onepassword_secret}"
    fi
}

# CRDs to be applied before the helmfile charts are installed
function apply_crds() {
    log debug "Applying CRDs"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/00-crds.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        log fatal "File does not exist" "file" "${helmfile_file}"
    fi

    if ! crds=$(helmfile --file "${helmfile_file}" template --quiet | yq eval-all --exit-status 'select(.kind == "CustomResourceDefinition")') || [[ -z "${crds}" ]]; then
        log fatal "Failed to render CRDs from Helmfile" "file" "${helmfile_file}"
    fi

    if echo "${crds}" | kubectl diff --filename - &>/dev/null; then
        log info "CRDs are up-to-date"
        return
    fi

    if ! echo "${crds}" | kubectl apply --server-side --filename - &>/dev/null; then
        log fatal "Failed to apply crds from Helmfile" "file" "${helmfile_file}"
    fi

    log info "CRDs applied successfully"
}

# Sync Helm releases
function sync_helm_releases() {
    log debug "Syncing Helm releases"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/01-apps.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        log error "File does not exist" "file=${helmfile_file}"
    fi

    if ! helmfile --file "${helmfile_file}" sync --hide-notes; then
        log error "Failed to sync Helm releases"
    fi

    log info "Helm releases synced successfully"
}

# Apply ClusterSecretStore for onepassword
function apply_clustersecretstore() {
    log debug "Applying ClusterSecretStore"

    local -r clustersecretstore="${ROOT_DIR}/bootstrap/onepassword-clustersecretstore.yaml"

    if [[ ! -f "${clustersecretstore}" ]]; then
        log warn "File does not exist" "file=${clustersecretstore}"
        return
    fi

    # Check if the ClusterSecretStore is up-to-date
    if kubectl diff --filename "${clustersecretstore}" &>/dev/null; then
        log info "ClusterSecretStore is up-to-date"
        return
    fi

    # Apply ClusterSecretStore
    if ! kubectl apply --server-side --filename "${clustersecretstore}" &>/dev/null; then
        log error "Failed to apply ClusterSecretStore"
        return
    fi

    log info "ClusterSecretStore applied successfully"
}

function main() {
    check_env KUBECONFIG TALOSCONFIG
    check_cli helmfile kubectl kustomize sops talhelper yq

    # Apply resources and Helm releases
    wait_for_nodes
    apply_namespaces
    apply_bootstrap_secrets
    apply_crds
    sync_helm_releases
    apply_clustersecretstore

    log info "Congrats! The cluster is bootstrapped and Flux is syncing the Git repository"
}

main "$@"
