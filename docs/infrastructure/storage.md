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

- Backs up PersistentVolumeClaims to S3-compatible storage
- Scheduled daily at 2 AM
- Component available at `kubernetes/components/volsync/`

### Garage

[Garage](https://garagehq.deuxfleurs.fr/) provides S3-compatible storage as the backup destination:

- Self-hosted within the cluster
- Used by VolSync and CloudNative-PG backups

### Kopia

[Kopia](https://kopia.io/) serves as the backup repository:

- Deduplication and encryption
- Works with VolSync for volume-level backups

## Snapshot Controller

The [snapshot-controller](https://github.com/kubernetes-csi/external-snapshotter) enables volume snapshots for point-in-time recovery.

## NFS Scaler Component

Located in `kubernetes/components/nfs-scaler/`, this KEDA-based component monitors NFS availability:

- Queries Prometheus for `probe_success{instance=~".+:2049"}` metric
- Scales deployments 0 → 1 when NFS is available
- Scales down to 0 when NFS is unavailable
- Prevents crash-loop storms when NFS is down

Apply to any app that mounts NFS volumes.
