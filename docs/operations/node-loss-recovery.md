# Node Loss Recovery

How to recover when a node is permanently lost (hardware failure, rebuild, etc.) and you've been left with orphaned PVCs that block stateful apps.

## Why this happens

The cluster uses **OpenEBS hostpath** as the default StorageClass for stateful workloads. Hostpath gives fast local-disk performance with minimal operational overhead, but each PV is hard-affined to the node that provisioned it:

```yaml
nodeAffinity:
  required:
    nodeSelectorTerms:
      - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values: ["node-01-pve"]
```

When a node is permanently lost (rebuild, hardware death, replacement), every PV pinned to it becomes inaccessible. Pods that mount those PVCs stay in `Init` or `Pending` forever with messages like:

```
MountVolume.NewMounter initialization failed for volume "pvc-xxx" :
  path "/var/mnt/local-hostpath/pvc-xxx" does not exist
```

This is by design — local storage trades durability for speed. The recovery model is:

| Workload type | Recovery source |
|---|---|
| HA databases (CNPG, MariaDB Galera) | Replicate from surviving instances |
| Single-instance apps with VolSync (forgejo, teslamate, plane, etc.) | Restore from VolSync (Kopia repo on NFS) |
| Apps with their own S3 backup cronjob (Kanidm) | Restore from S3 (Garage) via app-specific restore command |
| CNPG-backed stateless apps (kguardian, teslamate, penpot) | Heal automatically once Postgres is up |
| Stale/removed apps | Just delete the orphan resources |

**Note on app-specific backups:** Some apps run their own scheduled backup cronjobs that ship to Garage S3 (e.g., `kanidm-backup-sync` does `aws s3 sync /data/backups/ s3://kanidm/backups/` hourly). These are easy to miss because they aren't VolSync — check `kubectl get cronjob -A | grep -i backup` when triaging.

We don't use distributed storage (Longhorn / Rook-Ceph) because nodes have limited disk and we'd rather keep the hot path local and ship durability off-node via WAL streaming (CNPG → Garage S3) or scheduled snapshots (VolSync → Kopia → NFS).

## Triage checklist

When you spot a node-loss situation, work through this in order:

```bash
# Which workloads are wedged on missing volumes?
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Which Flux resources are unhealthy?
flux get ks -A --status-selector ready=false
flux get hr -A --status-selector ready=false

# Which PVs are pinned to the dead node?
kubectl get pv -o json | jq -r '
  .items[] |
  select(.spec.nodeAffinity.required.nodeSelectorTerms[]?.matchExpressions[]?.values[]? == "<dead-node>") |
  "\(.spec.claimRef.namespace)/\(.spec.claimRef.name) \(.metadata.name)"'
```

Categorize each affected workload:

1. **CNPG / MariaDB instance** → see [HA database](#ha-database-recovery)
2. **VolSync-backed app** → see [Single-instance with VolSync](#single-instance-app-recovery-volsync)
3. **Stateless app stuck on a downstream DB init** → leave alone, will self-heal once the DB is back
4. **Removed/stale resource** → just delete

## HA database recovery

The data layer is already replicated at the app level. Recovery is "delete the orphaned PVC and let the operator re-init a fresh replica on a live node."

### MariaDB Galera (the easy case)

If only one instance was on the dead node and the surviving members still have quorum (or can reach quorum), the operator handles everything once the orphan is removed.

```bash
# Delete the orphaned data + galera state PVCs for the dead instance
kubectl delete pvc -n database storage-mariadb-<N> galera-mariadb-<N>

# Force-delete the stuck pod
kubectl delete pod -n database mariadb-<N> --force --grace-period=0

# Watch the operator re-provision and the cluster come back
kubectl get pod -n database -l app.kubernetes.io/instance=mariadb -w
kubectl get mariadb -n database
```

The operator (with `spec.galera.recovery.enabled: true`) detects the missing instance, provisions fresh PVCs on a live node, and Galera SST-syncs the new replica from a healthy donor.

If the cluster has lost quorum (all surviving instances crashlooping with `failed to reach primary view`), you need force-bootstrap:

```bash
# Pick the survivor with the highest grastate seqno (or just the original primary)
kubectl patch mariadb -n database mariadb --type=merge -p '
spec:
  galera:
    recovery:
      forceClusterBootstrapInPod: mariadb-0
'
```

This is a temporary patch the operator clears after bootstrap. If Flux is reconciling the CR, suspend the ks first or it'll get reverted before the bootstrap completes.

If force-bootstrap fails (corrupted grastate, etc.), fall back to S3 restore using the scheduled `backup.k8s.mariadb.com` resource pointing at Garage.

### CloudNative-PG (the trickier case)

CNPG won't auto-clean dangling PVCs (by design — protects against accidental data loss). The danger is that the lost instance was the **primary**, in which case you need a switchover before deleting the PVC, otherwise the operator gets stuck trying to keep a dead instance as primary.

**Step 1 — check who's primary:**

```bash
kubectl get cluster -n database postgres -o jsonpath='
currentPrimary={.status.currentPrimary}
targetPrimary={.status.targetPrimary}
phase={.status.phase}
danglingPVC={.status.danglingPVC}
readyInstances={.status.readyInstances}/{.status.instances}
'
```

If `currentPrimary` is the dead-node instance, you need to force a switchover before the PVC delete.

**Step 2 — switchover (if needed):**

If you have the `cnpg` kubectl plugin:
```bash
kubectl cnpg promote postgres-3 -n database
```

Without the plugin, patch the cluster status directly:
```bash
kubectl patch cluster postgres -n database --subresource=status --type=merge -p '
{"status":{"targetPrimary":"postgres-3","currentPrimary":"postgres-3"}}
'
```

**Step 3 — delete the orphaned PVC and stuck pod:**

```bash
kubectl delete pod -n database postgres-<dead-N> --force --grace-period=0
kubectl delete pvc -n database postgres-<dead-N>
```

The PV has `Delete` reclaim policy, so it goes too. The operator now sees `instances: 3` but only 2 PVCs, and creates a fresh `postgres-<next>` via pg_basebackup from the new primary.

**Step 4 — kick the new primary if it's stuck in "Waiting for the new primary to be available":**

If the new primary was previously a replica, its on-disk state may say "I'm a replica of the old primary." The instance manager waits for someone to promote it. Restarting the pod re-reads the cluster's `currentPrimary` and triggers the local promotion:

```bash
kubectl delete pod -n database postgres-<new-primary>
```

Verify with:
```bash
kubectl exec -n database postgres-<new-primary> -c postgres -- \
  psql -U postgres -c 'SELECT pg_is_in_recovery();'   # should return f
kubectl get endpoints -n database postgres-rw          # should have an IP
```

**Step 5 — dangling PVCs:**

If other instance PVCs were also `dangling` (e.g., from a previous failed reconcile), the operator re-adopts them on its next loop. You can confirm by re-reading `.status.danglingPVC` — it should drain to empty as instance pods come up.

## Single-instance app recovery (VolSync)

For apps with no app-layer replication, VolSync's Kopia repo on NFS is the recovery point. Use the existing `scripts/volsync-restore-all.sh` for mass restores, or this single-app flow for one app at a time.

### Flow

```bash
APP=forgejo           # PVC name = RD name prefix
NS=utils              # target namespace
KS_NS=utils           # Flux Kustomization namespace (often same as target)

# 1. Suspend Flux so it doesn't fight us
flux suspend ks -n "${KS_NS}" "${APP}"

# 2. Scale down so nothing holds the PVC
kubectl -n "${NS}" scale deployment "${APP}" --replicas=0
kubectl -n "${NS}" wait pod -l app.kubernetes.io/name="${APP}" --for=delete --timeout=60s

# 3. Suspend the ReplicationSource (so it doesn't try to back up the empty PVC)
kubectl -n "${NS}" patch replicationsource "${APP}" --type=merge -p '{"spec":{"paused":true}}'

# 4. Delete the orphaned PVC + VolSync source cache
kubectl -n "${NS}" delete pvc "${APP}" "volsync-src-${APP}-cache" --wait=false

# 5. If a PVC is stuck Terminating on a missing PV finalizer, force-clear it:
kubectl -n "${NS}" patch pvc "${APP}" --type=merge -p '{"metadata":{"finalizers":null}}'

# 6. Recreate the destination PVC with the same spec but no node affinity.
#    Pull size/storageClass from the original Helm values, or use what's typical.
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP}
  namespace: ${NS}
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 10Gi } }
  storageClassName: openebs-hostpath
EOF

# 7. Trigger restore from latest snapshot
TRIGGER="restore-$(date -u +%Y%m%d-%H%M%S)"
kubectl -n "${NS}" patch replicationdestination "${APP}-dst" --type=json -p "[
  {\"op\":\"remove\",\"path\":\"/spec/kopia/restoreAsOf\"},
  {\"op\":\"replace\",\"path\":\"/spec/trigger/manual\",\"value\":\"${TRIGGER}\"}
]"

# 8. Wait for the restore to complete
until [[ "$(kubectl -n "${NS}" get replicationdestination "${APP}-dst" \
    -o jsonpath='{.status.lastManualSync}')" == "${TRIGGER}" ]]; do sleep 10; done
kubectl -n "${NS}" get replicationdestination "${APP}-dst" \
  -o jsonpath='result={.status.latestMoverStatus.result}{"\n"}'

# 9. Resume the source backup and Flux
kubectl -n "${NS}" patch replicationsource "${APP}" --type=merge -p '{"spec":{"paused":false}}'
flux resume ks -n "${KS_NS}" "${APP}"

# 10. Helm/Flux often won't reset replicas back from 0 on a no-op reconcile.
#     Scale the workload up manually:
kubectl -n "${NS}" scale deployment "${APP}" --replicas=1
```

### Why this differs from the mass-restore script

`volsync-restore-all.sh` uses VolSync's `copyMethod: Direct` to restore into the **existing** PVC. That works when the PVC is on a live node and you just want to roll back data — but in our case the PVC is bound to a PV on a dead node, so we have to delete and recreate it before the mover can mount it on a live node.

The destination Kopia mover provisions the cache PVC on first use. Watch for `Pending` PVCs — if the OpenEBS provisioner is itself wedged (e.g., its pod was on the dead node and is still pulling its image after rescheduling), the whole chain stalls. `kubectl get pod -n openebs-system` is the first thing to check if mover pods stay `Pending` with no events.

## App-specific S3 restore (Kanidm pattern)

Some apps (notably Kanidm) ship JSON-format backups to a Garage S3 bucket via a CronJob, separate from VolSync. The data PVC has no off-node copy on its own — the backup files in S3 are the only recovery point.

Pattern, using Kanidm as the example:

```bash
NS=identity
APP=kanidm
PVC=kanidm-data-kanidm-default-0   # StatefulSet PVC name
S3_BUCKET=kanidm                   # Garage bucket
TLS_SECRET=kanidm-tls              # if kanidmd needs TLS for restore

# 1. Suspend Flux so kaniop doesn't fight us
flux suspend ks -n "${NS}" "${APP}"

# 2. Scale the StatefulSet to 0 (orphan pod was Pending on dead node anyway)
kubectl -n "${NS}" scale statefulset kanidm-default --replicas=0
kubectl -n "${NS}" wait pod kanidm-default-0 --for=delete --timeout=60s || true

# 3. Delete the orphaned PVC; if Terminating-stuck, clear finalizer
kubectl -n "${NS}" delete pvc "${PVC}" --wait=false
kubectl -n "${NS}" patch pvc "${PVC}" --type=merge -p '{"metadata":{"finalizers":null}}'
```

For Kanidm, the operator (kaniop) re-creates the PVC immediately from the volumeClaimTemplate even with the StatefulSet at 0 replicas — there's no need to recreate it manually. Verify with `kubectl get pvc -n identity`.

```bash
# 4. Run a Job that downloads + decompresses + restores into the new empty PVC
#    Notes:
#      - The kanidm/server image has no shell (sh/gunzip) — use a busybox/alpine
#        sidecar to decompress before invoking kanidmd directly.
#      - The kanidm-s3-secret credentials work against Garage with
#        `--region us-east-1 --endpoint-url http://garage.volsync-system.svc.cluster.local:3900`.
#        Use `s3api get-object` rather than `s3 cp` — Garage 400s on the HEAD
#        request `s3 cp` issues first.
#      - `kanidmd database restore` requires KANIDM_TLS_CHAIN + KANIDM_TLS_KEY env
#        even though it never starts the network listener.
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: { name: kanidm-restore, namespace: identity }
spec:
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      securityContext: { fsGroup: 999, runAsUser: 999, runAsGroup: 999 }
      initContainers:
      - name: download
        image: amazon/aws-cli:latest
        command: ["sh","-c"]
        args:
        - |
          set -eux
          LATEST=$(aws --region us-east-1 --endpoint-url "$S3_ENDPOINT" s3 ls s3://kanidm/backups/ | awk '{print $NF}' | sort | tail -1)
          aws --region us-east-1 --endpoint-url "$S3_ENDPOINT" s3api get-object \
            --bucket kanidm --key "backups/${LATEST}" /tmp/backup.json.gz
        env:
        - { name: S3_ENDPOINT,        value: http://garage.volsync-system.svc.cluster.local:3900 }
        - { name: AWS_DEFAULT_REGION, value: us-east-1 }
        - { name: AWS_ACCESS_KEY_ID,     valueFrom: { secretKeyRef: { name: kanidm-s3-secret, key: AWS_ACCESS_KEY_ID } } }
        - { name: AWS_SECRET_ACCESS_KEY, valueFrom: { secretKeyRef: { name: kanidm-s3-secret, key: AWS_SECRET_ACCESS_KEY } } }
        volumeMounts: [ { name: tmp, mountPath: /tmp } ]
      - name: decompress
        image: alpine:3
        command: ["sh","-c"]
        args: ["set -eux; gunzip /tmp/backup.json.gz"]
        volumeMounts: [ { name: tmp, mountPath: /tmp } ]
      containers:
      - name: restore
        image: docker.io/kanidm/server:1.10.0
        command: ["kanidmd"]
        args:    ["database", "restore", "/tmp/backup.json"]
        env:
        - { name: KANIDM_DOMAIN,    value: auth.00o.sh }
        - { name: KANIDM_ORIGIN,    value: https://auth.00o.sh }
        - { name: KANIDM_DB_PATH,   value: /data/kanidm.db }
        - { name: KANIDM_TLS_CHAIN, value: /etc/kanidm/tls/tls.crt }
        - { name: KANIDM_TLS_KEY,   value: /etc/kanidm/tls/tls.key }
        volumeMounts:
        - { name: kanidm-data,  mountPath: /data }
        - { name: tmp,          mountPath: /tmp }
        - { name: kanidm-certs, mountPath: /etc/kanidm/tls, readOnly: true }
      volumes:
      - { name: kanidm-data,  persistentVolumeClaim: { claimName: kanidm-data-kanidm-default-0 } }
      - { name: tmp,          emptyDir: {} }
      - { name: kanidm-certs, secret: { secretName: kanidm-tls } }
EOF

# 5. Wait for restore Job and inspect logs
kubectl -n identity wait --for=condition=Complete job/kanidm-restore --timeout=10m
kubectl -n identity logs job/kanidm-restore -c restore | tail -5
# Expected: "✅ Restore Success!"

# 6. Scale StatefulSet back up and resume Flux
kubectl -n identity scale statefulset kanidm-default --replicas=1
flux resume ks -n identity kanidm
```

After Kanidm is healthy, **bounce any OIDC clients** (forgejo, dbgate, kubevirt-manager, opencost, penpot) — they often cache the previous discovery doc and need a restart to re-register against the restored identity store.

### Credential mismatch after a Kanidm restore (gotcha)

After the restore Job completes and Kanidm starts up, you'll likely see kaniop logs spamming `client failed to authenticate: AuthenticationFailed` for every reconcile (KanidmGroup, KanidmPersonAccount, KanidmOAuth2Client). This blocks OAuth2 client registration, which in turn blocks OIDC consumers like forgejo (its `configure-gitea` init container hits a 302 on the well-known discovery URL because the client isn't registered).

The cause: kaniop authenticates as `admin` / `idm_admin` using passwords stored in the `kanidm-admin-passwords` Secret. The restore may bring in a DB whose internal credential state for those accounts doesn't match what's in the Secret (this is a known kaniop+restore interaction). The fix is to reset the passwords on the restored DB to match what kaniop expects — or, easier, reset them to fresh values and update the Secret.

```bash
# 1. Stop kanidmd so we can use the offline recover-account command
flux suspend ks -n identity kanidm
kubectl -n identity scale statefulset kanidm-default --replicas=0
kubectl -n identity wait pod kanidm-default-0 --for=delete --timeout=60s

# 2. Run recover-account for admin (generates a new password, prints to stdout)
#    Note: kanidm/server image has no shell — invoke kanidmd directly via command/args.
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: { name: kanidm-recover-admin, namespace: identity }
spec:
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      securityContext: { fsGroup: 999, runAsUser: 999, runAsGroup: 999 }
      containers:
      - name: recover
        image: docker.io/kanidm/server:1.10.0
        command: ["kanidmd"]
        args:    ["recover-account", "admin"]
        env:
        - { name: KANIDM_DOMAIN,    value: auth.00o.sh }
        - { name: KANIDM_ORIGIN,    value: https://auth.00o.sh }
        - { name: KANIDM_DB_PATH,   value: /data/kanidm.db }
        - { name: KANIDM_TLS_CHAIN, value: /etc/kanidm/tls/tls.crt }
        - { name: KANIDM_TLS_KEY,   value: /etc/kanidm/tls/tls.key }
        volumeMounts:
        - { name: kanidm-data,  mountPath: /data }
        - { name: kanidm-certs, mountPath: /etc/kanidm/tls, readOnly: true }
      volumes:
      - { name: kanidm-data,  persistentVolumeClaim: { claimName: kanidm-data-kanidm-default-0 } }
      - { name: kanidm-certs, secret: { secretName: kanidm-tls } }
EOF
kubectl -n identity wait --for=condition=Complete job/kanidm-recover-admin --timeout=2m
ADMIN_PW=$(kubectl -n identity logs job/kanidm-recover-admin | grep -oP 'new_password: "\K[^"]+')
echo "admin: $ADMIN_PW"

# 3. Same for idm_admin (don't run in parallel — Kanidm DB is RWO)
#    Apply identical Job with name=kanidm-recover-idm-admin, args=["recover-account","idm_admin"].
IDM_PW=$(kubectl -n identity logs job/kanidm-recover-idm-admin | grep -oP 'new_password: "\K[^"]+')

# 4. Patch the Secret with the new passwords
kubectl patch secret -n identity kanidm-admin-passwords --type=json -p "[
  {\"op\":\"replace\",\"path\":\"/data/ADMIN_PASSWORD\",\"value\":\"$(printf '%s' "$ADMIN_PW" | base64 -w0)\"},
  {\"op\":\"replace\",\"path\":\"/data/IDM_ADMIN_PASSWORD\",\"value\":\"$(printf '%s' "$IDM_PW" | base64 -w0)\"}
]"

# 5. Scale Kanidm back up and resume Flux
kubectl -n identity scale statefulset kanidm-default --replicas=1
flux resume ks -n identity kanidm
```

Within ~30s of the Secret patch, kaniop should pick up the change (it watches the Secret), authenticate successfully, and start successfully reconciling all `KanidmOAuth2Client` and `KanidmPersonAccount` resources. Watch with:

```bash
kubectl -n identity logs deploy/kaniop -f | grep -iE 'auth|reconcil|fail'
```

Once you see `reconciling oauth2 client` INFO lines (not ERROR lines), bounce the OIDC consumers.

## Stale / removed resources

Apps that have been removed from Flux (commented out in a parent kustomization) sometimes leave behind cluster resources that aren't pruned. ReplicationDestinations are a common one — they keep spawning mover pods that fail to schedule because the source PVC no longer exists.

Just delete them:

```bash
kubectl delete replicationdestination -n <namespace> <app>-dst
```

The bound `volsync-dst-<app>-dst-cache` PVC will GC when its owner is gone.

## Recovering broken CNPG WAL archiving

WAL archiving can silently break for weeks if you're not monitoring `Cluster.status.conditions[?(@.type=="ContinuousArchiving")]`. The most common breakage after a recovery: forced primary promotions create new timelines, and barman-cloud's pre-archive check refuses to resume against an existing archive whose timeline state doesn't match the new primary's.

The symptom in the `plugin-barman-cloud` sidecar logs:

```
barman-cloud-check-wal-archive checking the first wal
ERROR: WAL archive check failed for server postgres: Expected empty archive
```

Even though the bucket may look mostly empty (because retention pruning ate the old WAL segments), the residual `<timeline>.history` files and base backup directories are enough to fail the check.

**Fix: switch to a fresh barman serverName** so a clean archive starts in a new prefix, preserving the orphaned data for posterity.

```yaml
# kubernetes/apps/database/<cluster>/cluster/cluster.yaml
spec:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: cnpg-garage
        serverName: postgres-r2     # bump this each time the archive needs reset
```

After applying the spec change:

1. The Cluster's `plugin-barman-cloud` sidecar caches barman config at startup, so you must **restart the primary pod** for the new `serverName` to take effect. (Sequential restart of replicas first then primary is cleaner; or just delete the primary pod and let CNPG fail over to a replica.)
2. Watch the plugin logs on the new primary — you should see options ending with `s3://cnpg/postgres-r2` instead of `s3://cnpg/postgres`:
   ```bash
   kubectl logs -n database <new-primary> -c plugin-barman-cloud -f | grep -E 'serverName|empty|archive'
   ```
3. Verify the cluster conditions flip:
   ```bash
   kubectl get cluster -n database postgres -o jsonpath='{.status.conditions}' \
     | python3 -c 'import sys,json;[print(c["type"],c["status"]) for c in json.loads(sys.stdin.read())]'
   ```
   You want `ContinuousArchiving: True` and `LastBackupSucceeded: True`.
4. CNPG will automatically take a fresh base backup once archiving works (or you can trigger one with `kubectl create backup ...`). Without a fresh base backup, the WAL stream you're now archiving has nothing to apply against — no recovery point.
5. The orphaned `s3://cnpg/<old-name>/` prefix stays in Garage. If you want to GC it, do so manually after confirming no other systems reference it.

**Always alert on `ContinuousArchiving` and `LastBackupSucceeded`.** Without those, your "last backup" timestamp can lie for months.

## Architectural caveats

A few things this design depends on, which you should verify periodically:

- **CNPG WAL archiving must actually work.** The cluster spec uses `barman-cloud.cloudnative-pg.io` to ship WAL to Garage. If `status.conditions[?(@.type=="ContinuousArchiving")].status == "False"` for any extended period, the "last backup" timestamp lies — you don't have a real recovery point. Alert on this. As of writing, archiving has been broken since 2026-01-29 and the last successful base backup was 2026-03-21, which made the node-01 incident a much bigger event than expected.
- **VolSync `ReplicationSource` must actually be running on schedule.** If a source pod can't run (e.g., its working cache PVC is on a dead node), backups silently stop. Check `kubectl get replicationsource -A` periodically — a stale `LAST SYNC` means no fresh recovery point.
- **OpenEBS provisioner placement.** The `openebs-localpv-provisioner` Deployment can land on any node. If it's on the node that dies, every new PVC provision request stalls until the provisioner reschedules and re-pulls. Not catastrophic, just adds latency to recovery.
- **`kubectl cnpg` plugin should be installed.** The status-patch workaround for promotion works but it's brittle — the plugin's `promote` command is the supported path. Add it to `.mise.toml` if you don't already have it.

## See also

- [Backup & Recovery](backup-recovery.md) — VolSync architecture, Kopia repo layout, S3 backups
- [Day-2 Operations](day2.md) — Routine operations
- `scripts/volsync-restore-all.sh` — Bulk restore script in the repository root
