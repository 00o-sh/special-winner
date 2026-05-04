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

### Onboarding a new app

The repository's standard pattern is **one shared cluster, per-app database + role**, provisioned by an `init-db` initContainer using `ghcr.io/home-operations/postgres-init`. The init container reads `INIT_POSTGRES_SUPER_PASS` (from the `cloudnative-pg` 1Password item) and creates the database and a non-superuser role for the app.

```yaml
initContainers:
  init-db:
    image:
      repository: ghcr.io/home-operations/postgres-init
      tag: 18@sha256:...
    envFrom:
      - secretRef:
          name: <app>-secret
```

The matching `ExternalSecret` template:

```yaml
template:
  data:
    INIT_POSTGRES_DBNAME: "{{ .APP_POSTGRES_DB }}"
    INIT_POSTGRES_HOST: postgres-rw.database.svc.cluster.local
    INIT_POSTGRES_PORT: "5432"
    INIT_POSTGRES_USER: "{{ .APP_POSTGRES_USER }}"
    INIT_POSTGRES_PASS: "{{ .APP_POSTGRES_PASSWORD }}"
    INIT_POSTGRES_SUPER_PASS: "{{ .POSTGRES_SUPER_PASS }}"
```

Apps then connect with their own role (`DATABASE_USER`/`DATABASE_PASS`).

### Apps that need PostgreSQL extensions

`CREATE EXTENSION` for "trusted" extensions like `pgcrypto` or `uuid-ossp` works as a regular role, but **`cube`, `earthdistance`, `postgis`, `pg_stat_statements`, etc. require superuser**. The per-app role created by `init-db` is intentionally **not** a superuser, so any migration that tries to install these extensions will fail with:

```
ERROR 42501 (insufficient_privilege) permission denied to create extension "earthdistance"
hint: Must be superuser to create this extension.
```

Pre-create the extensions in a second initContainer that connects as the postgres superuser. Example from TeslaMate (`kubernetes/apps/observability/teslamate/app/helmrelease.yaml`):

```yaml
initContainers:
  init-db:
    image:
      repository: ghcr.io/home-operations/postgres-init
      tag: 18@sha256:...
    envFrom:
      - secretRef:
          name: teslamate-secret
  init-extensions:
    image:
      repository: ghcr.io/home-operations/postgres-init
      tag: 18@sha256:...
    command:
      - /bin/sh
      - -c
      - |
        PGPASSWORD="$INIT_POSTGRES_SUPER_PASS" psql \
          -h "$INIT_POSTGRES_HOST" \
          -p "$INIT_POSTGRES_PORT" \
          -U postgres \
          -d "$INIT_POSTGRES_DBNAME" \
          -v ON_ERROR_STOP=1 \
          -v app_user="$INIT_POSTGRES_USER" <<'SQL'
        CREATE EXTENSION IF NOT EXISTS cube;
        CREATE EXTENSION IF NOT EXISTS earthdistance;

        DO $do$
        DECLARE stmt text;
        BEGIN
          SELECT string_agg(
                   format('ALTER FUNCTION %s OWNER TO %I',
                          p.oid::regprocedure::text, :'app_user'),
                   E';\n') || ';'
            INTO stmt
          FROM pg_proc p
          JOIN pg_depend d
            ON d.classid = 'pg_proc'::regclass
           AND d.objid   = p.oid
           AND d.deptype = 'e'
          JOIN pg_extension e ON e.oid = d.refobjid
          WHERE e.extname IN ('cube', 'earthdistance');

          IF stmt IS NOT NULL THEN
            EXECUTE stmt;
          END IF;
        END $do$;
        SQL
    envFrom:
      - secretRef:
          name: teslamate-secret
```

Notes:

- Reuse the `postgres-init` image — it already ships `psql` and matches the existing pattern.
- Connect as **`-U postgres`**, not as the app's role, so the `CREATE EXTENSION` succeeds.
- Use `CREATE EXTENSION IF NOT EXISTS` so the container is idempotent (Flux will reschedule it on every pod restart).
- Set `-v ON_ERROR_STOP=1` so a failed `CREATE EXTENSION` aborts the init and surfaces the error in pod events instead of silently letting the app start with a broken schema.
- **If the app's migrations also `ALTER FUNCTION` on extension members** (TeslaMate's `CreateGeoExtensions` does this for the `earthdistance` helpers), the postgres role that ran `CREATE EXTENSION` owns those functions — not the app role — so subsequent `ALTER FUNCTION` calls fail with `must be owner of function …`. Transfer ownership of every function attached to the extension to the app role, like the `DO` block above. Walking `pg_depend` rather than hard-coding function names keeps it forward-compatible with future extension upgrades.

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
- **S3 bucket**: `mariadb-backups` (prefix `galera`)
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
