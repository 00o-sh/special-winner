#!/usr/bin/env bash
# Restore all VolSync-backed PVCs to a specific point in time.
# Usage: ./scripts/volsync-restore-all.sh [RESTORE_DATE]
#   RESTORE_DATE: ISO-8601 date (default: 2026-03-01T23:59:59Z)
#
# What this script does:
#   1. Suspends all Flux Kustomizations for VolSync-backed apps
#   2. Scales down app workloads so PVCs can be deleted
#   3. Deletes the existing PVCs
#   4. Patches each ReplicationDestination with restoreAsOf + new trigger
#   5. Waits for all restores to complete
#   6. Resumes all Flux Kustomizations
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="info"

readonly RESTORE_AS_OF="${1:-2026-03-01T23:59:59Z}"
readonly RESTORE_TRIGGER="restore-$(date -u +%Y%m%d-%H%M%S)"
readonly FLUX_NS="flux-system"

# Format: "kustomization-name:target-namespace:app-name"
# kustomization-name is the metadata.name in ks.yaml
# target-namespace is the targetNamespace in ks.yaml
# app-name is the APP substitution variable (= PVC name = ReplicationDestination prefix)
readonly -a APPS=(
    "autobrr:media:autobrr"
    "bazarr:media:bazarr"
    "plex:media:plex"
    "prowlarr:media:prowlarr"
    "qbittorrent:media:qbittorrent"
    "radarr:media:radarr"
    "recyclarr:media:recyclarr"
    "seerr:media:seerr"
    "sonarr:media:sonarr"
    "tautulli:media:tautulli"
    "thelounge:media:thelounge"
    "qui:media:qui"
    "unifi-toolkit:network:unifi-toolkit"
    "gatus:observability:gatus"
    "forgejo:utils:forgejo"
    "penpot:utils:penpot"
)

function phase_suspend_kustomizations() {
    log info "Phase 1: Suspending Flux Kustomizations"
    for entry in "${APPS[@]}"; do
        local ks_name ns app
        ks_name="${entry%%:*}"
        ns="${entry#*:}"; ns="${ns%%:*}"
        app="${entry##*:}"
        log info "Suspending Kustomization" "ks=${ks_name}" "namespace=${ns}" "app=${app}"
        flux suspend ks -n "${FLUX_NS}" "${ks_name}" || log warn "Could not suspend ks ${ks_name}, may already be suspended"
    done
    log info "All Kustomizations suspended"
}

function phase_scale_down() {
    log info "Phase 2: Scaling down app workloads"
    for entry in "${APPS[@]}"; do
        local ns app
        ns="${entry#*:}"; ns="${ns%%:*}"
        app="${entry##*:}"
        # Try Deployment first, then StatefulSet — ignore errors (workload may have a different name)
        if kubectl -n "${ns}" get deployment "${app}" &>/dev/null; then
            log info "Scaling down Deployment" "app=${app}" "namespace=${ns}"
            kubectl -n "${ns}" scale deployment "${app}" --replicas=0
        elif kubectl -n "${ns}" get statefulset "${app}" &>/dev/null; then
            log info "Scaling down StatefulSet" "app=${app}" "namespace=${ns}"
            kubectl -n "${ns}" scale statefulset "${app}" --replicas=0
        else
            log warn "No Deployment or StatefulSet named '${app}' found in ${ns} — deleting pods directly"
            kubectl -n "${ns}" delete pods -l "app.kubernetes.io/name=${app}" --wait=false 2>/dev/null || true
        fi
    done

    log info "Waiting for pods to terminate (up to 60s)..."
    for entry in "${APPS[@]}"; do
        local ns app
        ns="${entry#*:}"; ns="${ns%%:*}"
        app="${entry##*:}"
        kubectl -n "${ns}" wait pods \
            --for=delete \
            -l "app.kubernetes.io/name=${app}" \
            --timeout=60s 2>/dev/null || true
    done
    log info "Workloads scaled down"
}

function phase_delete_pvcs() {
    log info "Phase 3: Deleting PVCs"
    for entry in "${APPS[@]}"; do
        local ns app
        ns="${entry#*:}"; ns="${ns%%:*}"
        app="${entry##*:}"
        if kubectl -n "${ns}" get pvc "${app}" &>/dev/null; then
            log info "Deleting PVC" "pvc=${app}" "namespace=${ns}"
            kubectl -n "${ns}" delete pvc "${app}" --wait=true
        else
            log warn "PVC not found, skipping" "pvc=${app}" "namespace=${ns}"
        fi
    done
    log info "PVCs deleted"
}

function phase_patch_replication_destinations() {
    log info "Phase 4: Patching ReplicationDestinations (restoreAsOf=${RESTORE_AS_OF}, trigger=${RESTORE_TRIGGER})"
    local patch
    patch=$(printf '{"spec":{"trigger":{"manual":"%s"},"kopia":{"restoreAsOf":"%s"}}}' \
        "${RESTORE_TRIGGER}" "${RESTORE_AS_OF}")

    for entry in "${APPS[@]}"; do
        local ns app
        ns="${entry#*:}"; ns="${ns%%:*}"
        app="${entry##*:}"
        local rd_name="${app}-dst"
        if kubectl -n "${ns}" get replicationdestination "${rd_name}" &>/dev/null; then
            log info "Patching ReplicationDestination" "rd=${rd_name}" "namespace=${ns}"
            kubectl -n "${ns}" patch replicationdestination "${rd_name}" \
                --type=merge -p "${patch}"
        else
            log warn "ReplicationDestination not found, skipping" "rd=${rd_name}" "namespace=${ns}"
        fi
    done
    log info "ReplicationDestinations patched"
}

function phase_wait_for_restores() {
    log info "Phase 5: Waiting for all restores to complete"
    local all_done failed=0

    for entry in "${APPS[@]}"; do
        local ns app
        ns="${entry#*:}"; ns="${ns%%:*}"
        app="${entry##*:}"
        local rd_name="${app}-dst"

        if ! kubectl -n "${ns}" get replicationdestination "${rd_name}" &>/dev/null; then
            log warn "ReplicationDestination not found, skipping wait" "rd=${rd_name}"
            continue
        fi

        log info "Waiting for restore" "rd=${rd_name}" "namespace=${ns}"
        local attempts=0
        while true; do
            local result
            result=$(kubectl -n "${ns}" get replicationdestination "${rd_name}" \
                -o jsonpath='{.status.latestMoverStatus.result}' 2>/dev/null || echo "")
            if [[ "${result}" == "Successful" ]]; then
                log info "Restore complete" "rd=${rd_name}" "namespace=${ns}"
                break
            elif [[ "${result}" == "Failed" ]]; then
                log warn "Restore FAILED" "rd=${rd_name}" "namespace=${ns}"
                failed=$((failed + 1))
                break
            fi
            attempts=$((attempts + 1))
            if ((attempts > 120)); then
                log warn "Restore timed out after 20m" "rd=${rd_name}" "namespace=${ns}"
                failed=$((failed + 1))
                break
            fi
            sleep 10
        done
    done

    if ((failed > 0)); then
        log warn "Some restores failed or timed out. Check ReplicationDestination status before resuming." \
            "failed=${failed}"
        read -r -p "Resume Kustomizations anyway? (y/N): " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            log info "Aborting resume. Run 'flux resume ks -n flux-system <name>' manually when ready."
            exit 1
        fi
    fi
    log info "Restore phase complete"
}

function phase_resume_kustomizations() {
    log info "Phase 6: Resuming Flux Kustomizations"
    for entry in "${APPS[@]}"; do
        local ks_name ns app
        ks_name="${entry%%:*}"
        ns="${entry#*:}"; ns="${ns%%:*}"
        app="${entry##*:}"
        log info "Resuming Kustomization" "ks=${ks_name}" "namespace=${ns}" "app=${app}"
        flux resume ks -n "${FLUX_NS}" "${ks_name}" || log warn "Could not resume ks ${ks_name}"
    done
    log info "All Kustomizations resumed — Flux will reconcile and bring apps back up"
}

function main() {
    check_env KUBECONFIG
    check_cli kubectl flux

    log info "VolSync mass restore" \
        "apps=${#APPS[@]}" \
        "restoreAsOf=${RESTORE_AS_OF}" \
        "trigger=${RESTORE_TRIGGER}"

    phase_suspend_kustomizations
    phase_scale_down
    phase_delete_pvcs
    phase_patch_replication_destinations
    phase_wait_for_restores
    phase_resume_kustomizations

    log info "Done. Monitor with: flux get ks -A"
}

main "$@"
