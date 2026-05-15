# Storage

The cluster uses multiple storage backends for different workload requirements.

## Storage Classes

| Class | Backend | Access Modes | Use Case |
|-------|---------|-------------|----------|
| `openebs-hostpath` | OpenEBS | RWO | Database volumes, high-performance local storage |
| `nfs-fast` | CSI Driver NFS | RWX | VM disks, shared media, multi-node access |

## OpenEBS

[OpenEBS](https://openebs.io/) provides cloud-native local storage:

- **hostpath** provisioner for fast local volumes
- Used by PostgreSQL, Dragonfly, and other stateful workloads
- CDI scratch space for VM disk imports

```
kubernetes/apps/openebs-system/openebs/
├── app/
│   ├── helmrelease.yaml
│   ├── ocirepository.yaml
│   └── kustomization.yaml
└── ks.yaml
```

## NFS Storage

CSI Driver NFS provides shared network storage:

- **ReadWriteMany** support for multi-node access
- Used for VM disks (enables live migration)
- Used for shared media storage
- NFS-scaler component prevents pods from crash-looping when NFS is unavailable

## Backup System

### VolSync

[VolSync](https://volsync.readthedocs.io/) handles volume replication and backup:

- Backs up PersistentVolumeClaims to the on-NFS **Kopia repository** at `/mnt/Speed/VolsyncKopia` (not Garage — VolSync's Kopia mover talks to a filesystem-backed repo, not S3)
- Scheduled daily at 2 AM, retention 24h/7d/4w/6m/2y
- Component available at `kubernetes/components/volsync/`
- Apps using it: forgejo, plex, sonarr, radarr, prowlarr, bazarr, autobrr, qbittorrent, qui, seerr, tautulli, thelounge, unifi-toolkit, gatus, penpot — see `scripts/volsync-restore-all.sh` for the canonical list

### Garage

[Garage](https://garagehq.deuxfleurs.fr/) provides S3-compatible storage. Single-replica deployment in the cluster:

- **Data dir** lives on NFS (`/mnt/Speed/Kubernetes/apps/garage/data/`) — safe there because object shards are append-only files, no locking required.
- **Meta dir** lives on a local `openebs-hostpath` PVC named `garage-meta`. LMDB (Garage's metadata store) does not work over NFS — file-lock semantics fail with `Resource temporarily unavailable`, leaving Garage running but unable to read its bucket/key tables. The PVC takes the meta off NFS.
- **Off-node meta durability**: a `backup-sync` sidecar inside the Garage pod rsyncs `/meta/` (minus the live `db.lmdb/` dir, which is exclusively locked) to NFS at `/mnt/Speed/Kubernetes/apps/garage/meta-backup/` every 24h. PrometheusRules `GarageMetaBackupSidecarRestarted` and `GarageMetaBackupSidecarAbsent` alert via AlertManager → Discord if the sidecar fails.
- **Used by**: CloudNative-PG (WAL + base backups), MariaDB Operator (scheduled backups), Kanidm (hourly JSON dumps via CronJob). Restore procedure documented in [Node Loss Recovery](../operations/node-loss-recovery.md#garage-metadata-recovery).

### Kopia

[Kopia](https://kopia.io/) is the backup repository used by VolSync's mover:

- Filesystem-type repository at `/mnt/Speed/VolsyncKopia` on the NAS
- Deduplication + encryption at rest
- One repo, multiple `sourceIdentity` namespaces (one per app)
- Repository credentials managed via the `volsync-template` 1Password item

## Snapshot Controller

The [snapshot-controller](https://github.com/kubernetes-csi/external-snapshotter) enables volume snapshots for point-in-time recovery.

## NFS Scaler Component

Located in `kubernetes/components/nfs-scaler/`, this KEDA-based component monitors NFS availability:

- Queries Prometheus for `probe_success{instance=~".+:2049"}` metric
- Scales deployments 0 → 1 when NFS is available
- Scales down to 0 when NFS is unavailable
- Prevents crash-loop storms when NFS is down

Apply to any app that mounts NFS volumes.
