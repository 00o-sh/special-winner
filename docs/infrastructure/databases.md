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
