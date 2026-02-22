# Databases

## CloudNative-PG (PostgreSQL)

[CloudNative-PG](https://cloudnative-pg.io/) runs a **PostgreSQL 17.7** high-availability cluster with 3 instances.

### Architecture

```
kubernetes/apps/database/cloudnative-pg/
├── app/                    # Operator deployment
│   ├── helmrelease.yaml
│   └── ocirepository.yaml
├── cluster/               # PostgreSQL cluster definition
│   ├── cluster.yaml       # Main cluster spec
│   ├── scheduledbackup.yaml
│   ├── objectstore.yaml   # S3 backup config
│   └── externalsecret.yaml
└── recovery/              # Disaster recovery configs
    └── cluster.yaml
```

### Configuration

| Setting | Value |
|---------|-------|
| Instances | 3 (HA with pod anti-affinity) |
| Storage | 20Gi per instance (openebs-hostpath) |
| Max connections | 200 |
| Shared buffers | 256MB |
| Effective cache size | 512MB |
| Maintenance work mem | 128MB |
| CPU request | 100m |
| Memory request | 512Mi |
| Memory limit | 2Gi |

### Backups

- **WAL archiving** to Garage S3 via barman-cloud plugin
- **Scheduled backups** with configurable retention
- **Monitoring** via PodMonitor for Prometheus

### Connecting

Applications connect via the internal service:

```
postgres-rw.database.svc.cluster.local:5432
```

### Recovery

A recovery cluster definition exists at `kubernetes/apps/database/cloudnative-pg/recovery/cluster.yaml` for disaster recovery scenarios.

## MariaDB Operator (MariaDB Galera)

[MariaDB Operator](https://github.com/mariadb-operator/mariadb-operator) runs a **MariaDB 11.7** high-availability Galera cluster with 3 instances.

### Architecture

```
kubernetes/apps/database/mariadb-operator/
├── app/                       # Operator deployment
│   ├── helmrelease-crds.yaml  # CRDs HelmRelease
│   ├── helmrelease.yaml       # Operator HelmRelease
│   ├── helmrepository.yaml    # Helm repo source
│   └── kustomization.yaml
├── cluster/                   # MariaDB Galera cluster
│   ├── mariadb.yaml          # MariaDB CR (Galera)
│   ├── backup.yaml           # Scheduled S3 backup
│   ├── externalsecret.yaml   # 1Password credentials
│   └── kustomization.yaml
└── ks.yaml                   # Flux Kustomizations
```

### Configuration

| Setting | Value |
|---------|-------|
| Instances | 3 (Galera multi-master with pod anti-affinity) |
| Storage | 20Gi per instance (openebs-hostpath) |
| Max connections | 200 |
| InnoDB buffer pool | 256MB |
| Max allowed packet | 256MB |
| CPU request | 100m |
| Memory request | 512Mi |
| Memory limit | 2Gi |

### Backups

- **Scheduled backups** to Garage S3 every 6 hours (`0 */6 * * *`)
- **Retention**: 30 days
- **Compression**: bzip2
- **S3 bucket**: `mariadb` (prefix `galera`)
- **Method**: `mysqldump` with `--single-transaction --all-databases`

### Connecting

Applications connect via internal services:

```
# All instances (load-balanced)
mariadb.database.svc.cluster.local:3306

# Primary only
mariadb-primary.database.svc.cluster.local:3306

# Read replicas
mariadb-secondary.database.svc.cluster.local:3306
```

### Operator Installation

The operator is installed via two separate HelmReleases from the `helm.mariadb.com` Helm repository:

1. **mariadb-operator-crds** — installs Custom Resource Definitions
2. **mariadb-operator** — installs the controller (depends on CRDs)

The operator includes Prometheus metrics via ServiceMonitor and cert-manager webhook integration.

### FreePBX Databases

The MariaDB cluster hosts [FreePBX](../applications/freepbx.md) databases managed via operator CRs in `kubernetes/apps/voip/freepbx/database/`:

| Resource | Name | Purpose |
|----------|------|---------|
| Database | `b1_asterisk` | Main Asterisk configuration |
| Database | `b1_asteriskcdrdb` | Call Detail Records |
| User | `freepbx` | Application user (max 100 connections) |
| Grant | `ALL PRIVILEGES` | Full access on both databases |

## Dragonfly

[Dragonfly](https://www.dragonflydb.io/) is a modern Redis-compatible in-memory datastore:

- Deploys the Dragonfly Operator for managing instances
- Higher performance alternative to Redis/Valkey
- Used by applications requiring fast caching or session storage

## DBGate

[DBGate](https://dbgate.org/) provides a web UI for database management:

- Located in `kubernetes/apps/database/dbgate/`
- Kanidm SSO integration for authentication
- Accessible via Envoy Gateway
