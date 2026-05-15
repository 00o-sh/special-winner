#!/usr/bin/env bash
# Restore all VolSync-backed PVCs to a specific point in time.
# Usage: ./scripts/volsync-restore-all.sh [RESTORE_DATE]
#   RESTORE_DATE: RFC3339 timestamp (default: 2026-03-01T23:59:59Z)
#
# What this script does:
#   1. Suspends all Flux Kustomizations for VolSync-backed apps
#   2. Scales down app workloads so PVCs are not actively written to
#   3. Patches each ReplicationDestination with restoreAsOf + new trigger
#      (copyMethod: Direct restores into the existing PVC — no PVC deletion needed;
#       enableFileDeletion: true in the component template removes stale files)
#   4. Waits for all restores to complete
#   5. Resumes all Flux Kustomizations
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="info"

readonly RESTORE_AS_OF="${1:-2026-03-01T23:59:59Z}"
readonly RESTORE_TRIGGER="restore-$(date -u +%Y%m%d-%H%M%S)"

# Format: "kustomization-name:ks-namespace:target-namespace:app-name"
#
# ks-namespace is where the Flux Kustomization CR lives.
# This is determined by the parent kustomization.yaml namespace: field:
#   kubernetes/apps/media/kustomization.yaml         → namespace: media
#   kubernetes/apps/network/kustomization.yaml       → namespace: network
#   kubernetes/apps/observability/kustomization.yaml → namespace: observability
#   kubernetes/apps/utils/kustomization.yaml         → namespace: utils
#
# target-namespace is the targetNamespace in ks.yaml (where the app pods/PVCs live).
# app-name is the APP substitution variable (= PVC name = ReplicationDestination prefix).
readonly -a APPS=(
    "autobrr:media:media:autobrr"
    "bazarr:media:media:bazarr"
    "plex:media:media:plex"
    "prowlarr:media:media:prowlarr"
    "qbittorrent:media:media:qbittorrent"
    "radarr:media:media:radarr"
    "recyclarr:media:media:recyclarr"
    "seerr:media:media:seerr"
    "sonarr:media:media:sonarr"
    "tautulli:media:media:tautulli"
    "thelounge:media:media:thelounge"
    "qui:media:media:qui"
    "unifi-toolkit:network:network:unifi-toolkit"
    "gatus:observability:observability:gatus"
    "forgejo:utils:utils:forgejo"
    "penpot:utils:utils:penpot"
)

function parse_entry() {
    # Usage: parse_entry <entry> <field>
    # Fields: ks_name=1, ks_ns=2, target_ns=3, app=4
    echo "${1}" | cut -d: -f"${2}"
}

function phase_suspend_kustomizations() {
    log info "Phase 1: Suspending Flux Kustomizations"
    for entry in "${APPS[@]}"; do
        local ks_name ks_ns
        ks_name="$(parse_entry "${entry}" 1)"
        ks_ns="$(parse_entry "${entry}" 2)"
        log info "Suspending Kustomization" "ks=${ks_name}" "ks-namespace=${ks_ns}"
        flux suspend ks -n "${ks_ns}" "${ks_name}" \
            || log warn "Could not suspend ${ks_name} in ${ks_ns}, may already be suspended"
    done
    log info "All Kustomizations suspended"
}

function phase_scale_down() {
    log info "Phase 2: Scaling down app workloads"
    for entry in "${APPS[@]}"; do
        local target_ns app
        target_ns="$(parse_entry "${entry}" 3)"
        app="$(parse_entry "${entry}" 4)"

        # Scale down ALL Deployments matching the app label (handles multi-controller
        # apps like penpot where names are penpot-frontend, penpot-backend, etc.)
        local deployments
        deployments=$(kubectl -n "${target_ns}" get deployments \
            -l "app.kubernetes.io/name=${app}" -o name 2>/dev/null || true)
        if [[ -n "${deployments}" ]]; then
            log info "Scaling down Deployments" "app=${app}" "namespace=${target_ns}"
            echo "${deployments}" | xargs -r kubectl -n "${target_ns}" scale --replicas=0
        fi

        local statefulsets
        statefulsets=$(kubectl -n "${target_ns}" get statefulsets \
            -l "app.kubernetes.io/name=${app}" -o name 2>/dev/null || true)
        if [[ -n "${statefulsets}" ]]; then
            log info "Scaling down StatefulSets" "app=${app}" "namespace=${target_ns}"
            echo "${statefulsets}" | xargs -r kubectl -n "${target_ns}" scale --replicas=0
        fi

        if [[ -z "${deployments}" && -z "${statefulsets}" ]]; then
            log warn "No Deployments/StatefulSets with label app.kubernetes.io/name=${app} in ${target_ns}"
        fi
    done

    log info "Waiting for pods to terminate (up to 60s)..."
    for entry in "${APPS[@]}"; do
        local target_ns app
        target_ns="$(parse_entry "${entry}" 3)"
        app="$(parse_entry "${entry}" 4)"
        # Only wait if pods actually exist — kubectl wait hangs until timeout when
        # no pods match the selector.
        local pod_count
        pod_count=$(kubectl -n "${target_ns}" get pods \
            -l "app.kubernetes.io/name=${app}" --no-headers 2>/dev/null | wc -l)
        if [[ "${pod_count}" -gt 0 ]]; then
            log info "Waiting for ${pod_count} pod(s) to terminate" \
                "app=${app}" "namespace=${target_ns}"
            kubectl -n "${target_ns}" wait pods \
                --for=delete \
                -l "app.kubernetes.io/name=${app}" \
                --timeout=60s 2>/dev/null || true
        fi
    done
    log info "Workloads scaled down"
}

function phase_patch_replication_destinations() {
    log info "Phase 3: Patching ReplicationDestinations" \
        "restoreAsOf=${RESTORE_AS_OF}" \
        "trigger=${RESTORE_TRIGGER}"

    local patch
    patch=$(printf '{"spec":{"trigger":{"manual":"%s"},"kopia":{"restoreAsOf":"%s"}}}' \
        "${RESTORE_TRIGGER}" "${RESTORE_AS_OF}")

    for entry in "${APPS[@]}"; do
        local target_ns app rd_name
        target_ns="$(parse_entry "${entry}" 3)"
        app="$(parse_entry "${entry}" 4)"
        rd_name="${app}-dst"
        if kubectl -n "${target_ns}" get replicationdestination "${rd_name}" &>/dev/null; then
            log info "Patching ReplicationDestination" "rd=${rd_name}" "namespace=${target_ns}"
            kubectl -n "${target_ns}" patch replicationdestination "${rd_name}" \
                --type=merge -p "${patch}"
        else
            log warn "ReplicationDestination not found, skipping" \
                "rd=${rd_name}" "namespace=${target_ns}"
        fi
    done
    log info "ReplicationDestinations patched"
}

function phase_wait_for_restores() {
    log info "Phase 4: Waiting for all restores to complete (polling every 10s, timeout 20m per app)"
    local failed=0

    for entry in "${APPS[@]}"; do
        local target_ns app rd_name
        target_ns="$(parse_entry "${entry}" 3)"
        app="$(parse_entry "${entry}" 4)"
        rd_name="${app}-dst"

        if ! kubectl -n "${target_ns}" get replicationdestination "${rd_name}" &>/dev/null; then
            log warn "ReplicationDestination not found, skipping wait" "rd=${rd_name}"
            continue
        fi

        log info "Waiting for restore" "rd=${rd_name}" "namespace=${target_ns}"
        local attempts=0
        while true; do
            local result
            result=$(kubectl -n "${target_ns}" get replicationdestination "${rd_name}" \
                -o jsonpath='{.status.latestMoverStatus.result}' 2>/dev/null || true)
            if [[ "${result}" == "Successful" ]]; then
                log info "Restore complete" "rd=${rd_name}" "namespace=${target_ns}"
                break
            elif [[ "${result}" == "Failed" ]]; then
                log warn "Restore FAILED — check mover logs" \
                    "rd=${rd_name}" "namespace=${target_ns}"
                log warn "  kubectl -n ${target_ns} logs -l volsync.backube/mover-owner-name=${rd_name} --tail=50"
                failed=$((failed + 1))
                break
            fi
            attempts=$((attempts + 1))
            if ((attempts > 120)); then
                log warn "Restore timed out after 20m" "rd=${rd_name}" "namespace=${target_ns}"
                failed=$((failed + 1))
                break
            fi
            sleep 10
        done
    done

    if ((failed > 0)); then
        log warn "Some restores failed or timed out" "count=${failed}"
        read -r -p "Resume Kustomizations anyway? Unhealthy apps will stay down. (y/N): " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            log info "Aborting resume. Fix failing restores then resume manually:"
            log info "  flux resume ks -n <ks-namespace> <app>"
            exit 1
        fi
    fi
    log info "Restore phase complete"
}

function phase_restore_garage_meta() {
    # garage-meta is NOT a VolSync-managed PVC (RWO + no CSI snapshot support
    # makes copyMethod=Direct unsafe; we corrupted the PVC trying it). It's
    # backed up by an in-pod sidecar that rsyncs /meta/ to NFS daily. Restore
    # = stop Garage, copy NFS → PVC, seed db.lmdb from the latest snapshot,
    # start Garage.
    log info "Phase 6: Restoring garage-meta from NFS"

    log info "Scaling Garage to 0"
    kubectl -n volsync-system scale deploy garage --replicas=0
    kubectl -n volsync-system wait pod \
        -l app.kubernetes.io/name=garage \
        --for=delete --timeout=60s 2>/dev/null || true

    log info "Applying garage-meta restore Job"
    kubectl delete job -n volsync-system garage-meta-restore --ignore-not-found
    kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: { name: garage-meta-restore, namespace: volsync-system }
spec:
  ttlSecondsAfterFinished: 600
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      securityContext: { fsGroup: 10000, runAsUser: 10000, runAsGroup: 10000 }
      containers:
      - name: restore
        image: alpine:3
        command: ["sh","-c"]
        args:
        - |
          set -eux
          LATEST=$(ls -1 /backup/snapshots 2>/dev/null | sort | tail -1)
          if [ -z "$LATEST" ]; then
            echo "FATAL: no snapshots found under /backup/snapshots/"; exit 1
          fi
          echo "Restoring from snapshot: $LATEST"
          find /dst -mindepth 1 -delete
          for f in cluster_layout data_layout node_key node_key.pub peer_list lifecycle_worker_state scrub_info; do
            [ -e "/backup/$f" ] && cp -v "/backup/$f" "/dst/$f"
          done
          chmod 600 /dst/node_key
          mkdir -p /dst/snapshots /dst/db.lmdb
          cp -rv /backup/snapshots/. /dst/snapshots/
          cp -v "/backup/snapshots/${LATEST}/db.lmdb" /dst/db.lmdb/data.mdb
        volumeMounts:
        - { name: backup, mountPath: /backup }
        - { name: dst,    mountPath: /dst }
      volumes:
      - name: backup
        nfs: { server: nas.3226texas.com, path: /mnt/Speed/Kubernetes/apps/garage/meta-backup }
      - name: dst
        persistentVolumeClaim: { claimName: garage-meta }
EOF

    log info "Waiting for restore Job to complete (timeout 10m)"
    if ! kubectl -n volsync-system wait --for=condition=Complete \
            job/garage-meta-restore --timeout=10m; then
        log warn "garage-meta restore Job did not complete"
        kubectl logs -n volsync-system -l job-name=garage-meta-restore --tail=30
        log warn "Continuing anyway; Garage will start with whatever's on the PVC"
    fi

    log info "Scaling Garage back to 1"
    kubectl -n volsync-system scale deploy garage --replicas=1
    log info "garage-meta restore complete"
}

function phase_resume_kustomizations() {
    log info "Phase 5: Resuming Flux Kustomizations"
    for entry in "${APPS[@]}"; do
        local ks_name ks_ns
        ks_name="$(parse_entry "${entry}" 1)"
        ks_ns="$(parse_entry "${entry}" 2)"
        log info "Resuming Kustomization" "ks=${ks_name}" "ks-namespace=${ks_ns}"
        flux resume ks -n "${ks_ns}" "${ks_name}" \
            || log warn "Could not resume ${ks_name} in ${ks_ns}"
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
    phase_patch_replication_destinations
    phase_wait_for_restores
    phase_restore_garage_meta
    phase_resume_kustomizations

    log info "Done. Monitor with: flux get ks -A && kubectl get replicationdestination -A"
}

main "$@"
