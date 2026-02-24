# PR 4: Make Garage storage independent per cluster

## Task

Move Garage's own data and metadata storage from NFS to local PVCs (openebs-hostpath). Each cluster's Garage instance becomes self-contained — its data lives on the cluster nodes, not on a site-specific NAS.

## Context

Currently, Garage stores both data and metadata on NFS:
- `data` → `nas.3226texas.com:/mnt/Speed/Kubernetes/apps/garage/data`
- `meta` → `nas.3226texas.com:/mnt/Speed/Kubernetes/apps/garage/meta`

This means Garage on usny01 can't function because it can't reach the 3226 NAS. After this PR, each cluster runs a fully independent Garage instance on local storage.

## Files to change

### 1. Garage HelmRelease

**File**: `kubernetes/apps/volsync-system/garage/app/helmrelease.yaml`

Change the persistence section from NFS to PVCs:

**Current** (lines ~130-141):
```yaml
persistence:
  config:
    enabled: true
    type: configMap
    name: garage
    globalMounts:
      - path: /etc/garage.toml
        subPath: configuration.toml
  data:
    type: nfs
    server: nas.3226texas.com
    path: /mnt/Speed/Kubernetes/apps/garage/data
    globalMounts:
      - path: /data
  meta:
    type: nfs
    server: nas.3226texas.com
    path: /mnt/Speed/Kubernetes/apps/garage/meta
    globalMounts:
      - path: /meta
```

**New:**
```yaml
persistence:
  config:
    enabled: true
    type: configMap
    name: garage
    globalMounts:
      - path: /etc/garage.toml
        subPath: configuration.toml
  data:
    type: persistentVolumeClaim
    storageClass: openebs-hostpath
    accessMode: ReadWriteOnce
    size: 50Gi
    globalMounts:
      - path: /data
  meta:
    type: persistentVolumeClaim
    storageClass: openebs-hostpath
    accessMode: ReadWriteOnce
    size: 5Gi
    globalMounts:
      - path: /meta
```

Adjust sizes based on current usage. Check the bjw-s app-template chart docs for exact PVC syntax — it may use `existingClaim` or `spec` instead of top-level `storageClass`/`size`.

### 2. Garage configuration

**File**: `kubernetes/apps/volsync-system/garage/app/resources/configuration.toml`

Verify `data_dir` and `metadata_dir` paths match the mount points (`/data` and `/meta`). These should already be correct since the mount paths aren't changing.

Check if `replication_factor = 1` is still appropriate. For a single-node Garage (which is the case per cluster), it must stay at 1.

## Data migration note

Existing Garage data on NFS will not be migrated. If Volsync was already cut over to S3 (PR 3), the Garage bucket will need to be recreated. This is effectively a fresh Garage instance per cluster.

Steps after deploying:
1. Garage starts with empty local storage
2. Re-create the `volsync` bucket and access keys via Garage admin API
3. Update 1Password with new access keys if they changed
4. Volsync begins backing up to the new empty repository

## Important: check both manifests and templates

The Garage HelmRelease is a committed manifest under `kubernetes/apps/`. Also check `templates/` for any `.j2` files that might reference Garage NFS paths — both must be updated together.

Run: `grep -r "nas\.\|garage/data\|garage/meta" kubernetes/apps/volsync-system/garage/ templates/`

## Validation

1. Verify Garage pod starts and is healthy (check `garage-api.00o.sh/health`)
2. Verify PVCs are created and bound
3. Verify Volsync can still write backups to Garage S3
4. Verify Kopia web UI still works

## Commit

Use semantic commit: `feat(volsync): migrate Garage storage from NFS to local PVCs`
