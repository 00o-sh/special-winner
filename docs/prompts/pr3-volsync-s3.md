# PR 3: Migrate Volsync from Kopia-filesystem (NFS) to Kopia-S3 (Garage)

## Task

Move the Volsync backup repository from NFS-mounted Kopia filesystem to Garage S3 API. After this change, Volsync mover jobs talk to Garage over HTTP instead of mounting NFS directly. This makes backups accessible from any cluster that can reach the Garage S3 endpoint.

## Context

### Current architecture
- Volsync component ExternalSecret creates secrets with `KOPIA_REPOSITORY: filesystem:///repository`
- A MutatingAdmissionPolicy (`volsync-mover-nfs`) injects an NFS volume mount into every Volsync mover Job
- A kustomization patch in `kubernetes/apps/volsync-system/kustomization.yaml` also injects NFS volumes into maintenance CronJobs and backup/restore Jobs
- A second MutatingAdmissionPolicy (`kopia-maintenance-nfs`) injects NFS into Kopia maintenance Jobs
- Kopia server (`volsync-system/kopia/`) mounts NFS at `/repository` for the web UI
- All of this depends on `nas.3226texas.com:/mnt/Speed/VolsyncKopia` being reachable

### Target architecture
- Volsync mover jobs use Kopia's S3 backend to talk to Garage at `garage-s3.volsync-system.svc.cluster.local:3900` (or the cluster-internal service)
- No NFS volume injection needed — remove both MutatingAdmissionPolicies for NFS
- No kustomization NFS patches needed — remove from `kubernetes/apps/volsync-system/kustomization.yaml`
- Kopia server uses S3 backend for its repository config
- Garage S3 credentials come from 1Password via ExternalSecret

## Files to change

### 1. Volsync component ExternalSecret

**File**: `kubernetes/components/volsync/externalsecret.yaml`

Change the template data from filesystem to S3:

**Current:**
```yaml
template:
  data:
    KOPIA_FS_PATH: /repository
    KOPIA_PASSWORD: "{{ .KOPIA_PASSWORD }}"
    KOPIA_REPOSITORY: filesystem:///repository
```

**New:**
```yaml
template:
  data:
    KOPIA_PASSWORD: "{{ .KOPIA_PASSWORD }}"
    AWS_ACCESS_KEY_ID: "{{ .GARAGE_S3_ACCESS_KEY_ID }}"
    AWS_SECRET_ACCESS_KEY: "{{ .GARAGE_S3_SECRET_ACCESS_KEY }}"
    KOPIA_S3_ENDPOINT: "garage.volsync-system.svc.cluster.local:3900"
    KOPIA_S3_BUCKET: volsync
    KOPIA_S3_REGION: USTX01
    KOPIA_S3_DISABLE_TLS: "true"
```

Note: The 1Password item `volsync-template` will need `GARAGE_S3_ACCESS_KEY_ID` and `GARAGE_S3_SECRET_ACCESS_KEY` fields added (user must do this manually in 1Password). The `KOPIA_PASSWORD` field already exists.

Check Kopia docs / Volsync docs for the exact env var names for S3. Kopia may use `KOPIA_S3_*` env vars or it may use `AWS_*` env vars. Verify by checking Kopia source or docs.

### 2. Remove volsync-mover-nfs MutatingAdmissionPolicy

**File**: `kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml`

This file contains two MutatingAdmissionPolicies:
- `volsync-mover-jitter` — KEEP this (adds random jitter to backup timing)
- `volsync-mover-nfs` — REMOVE this (injects NFS volume mount)

Remove the `volsync-mover-nfs` policy and its binding (the last two YAML documents in the file, starting around line 56).

### 3. Remove kopia-maintenance-nfs MutatingAdmissionPolicy

**File**: `kubernetes/apps/volsync-system/volsync/maintenance/mutatingadmissionpolicy.yaml`

This entire file is the `kopia-maintenance-nfs` policy. Delete the file entirely.

Update the kustomization.yaml in the same directory to remove the reference to this file.

### 4. Remove NFS patches from volsync-system kustomization

**File**: `kubernetes/apps/volsync-system/kustomization.yaml`

Remove both patch blocks:
- The patch targeting `CronJob` named `kopia-maint-daily-.*` (lines ~12-43)
- The patch targeting `Job` named `volsync-(src|dst)-.*` (lines ~44-76)

Keep the `components:`, `resources:`, and any non-NFS patches.

### 5. Update Kopia server to use S3 backend

**File**: `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml`

**repository.config** — change the storage type (in the configMap `config` → `repository.config`):

**Current:**
```json
{
  "storage": {
    "type": "filesystem",
    "config": {
      "path": "/repository"
    }
  },
  ...
}
```

**New:**
```json
{
  "storage": {
    "type": "s3",
    "config": {
      "bucket": "volsync",
      "endpoint": "garage.volsync-system.svc.cluster.local:3900",
      "region": "USTX01",
      "doNotUseTLS": true
    }
  },
  ...
}
```

**Persistence** — remove the NFS repository mount:

Remove this block from `persistence:`:
```yaml
repository:
  type: nfs
  server: nas.3226texas.com
  path: /mnt/Speed/VolsyncKopia
  globalMounts:
    - path: /repository
```

**Secrets** — Kopia needs S3 credentials. Either:
- Add `envFrom` referencing a secret with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Or create a separate ExternalSecret for Kopia's S3 credentials

### 6. Update KopiaMaintenance if needed

Check `kubernetes/apps/volsync-system/volsync/maintenance/kopiamaintenance.yaml` — if it references NFS paths or filesystem-specific config, update accordingly.

### 7. Create Garage S3 bucket

Add a Job or init container that creates the `volsync` bucket in Garage. Or document that the user needs to create it manually via the Garage admin API:
```bash
garage bucket create volsync
garage key create volsync-key
garage bucket allow volsync --read --write --owner --key volsync-key
```

## Data migration note

Existing backups on NFS will NOT be accessible after this change. This is a clean start for the S3-backed repository. If the user wants to migrate existing snapshots, they can use `kopia repository sync-to` before cutting over, but that's a manual step outside this PR.

## Important: check both manifests and templates

All files listed above are committed manifests under `kubernetes/` — these are the files Flux reads directly. But also search `templates/` for any `.j2` template files that render NFS-related config (e.g., if PR2 converted MutatingAdmissionPolicy files to Jinja2 templates). Both must be updated together.

Run: `grep -r "nas\.\|VolsyncKopia\|/repository" kubernetes/apps/volsync-system/ templates/`

## Validation

1. After deploying, verify Volsync mover jobs start without NFS mount errors
2. Verify Kopia web UI at `kopia.00o.sh` connects to the S3 repository
3. Trigger a manual backup and verify it lands in Garage S3
4. Trigger a manual restore and verify data is recovered

## Commit

Use semantic commit: `feat(volsync): migrate backup repository from NFS filesystem to Garage S3`
