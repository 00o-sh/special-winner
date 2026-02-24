# Multi-Cluster Migration — PR Prompts

Each file below is a self-contained prompt you can paste into a new Claude Code session to implement that PR. They are ordered by dependency chain.

## Dependency graph

```
PR 1 (add variables)
  └─▶ PR 2 (parameterize NFS/NAS references)
        ├─▶ PR 3 (Volsync → S3)
        │     └─▶ PR 4 (Garage local storage)
        │           └─▶ PR 5 (Garage cross-site replication)
        └─▶ PR 6 (fix failover workload shutdown)
```

PR 6 is the most impactful — without it, failover doesn't actually work for active→standby transitions. It can be started in parallel with PRs 3-5 once PR 2 lands.

## Prompts

| PR | File | Description |
|----|------|-------------|
| 1 | [pr1-cluster-variables.md](pr1-cluster-variables.md) | Add cluster-specific variables to cluster-secrets and templates |
| 2 | [pr2-parameterize-references.md](pr2-parameterize-references.md) | Parameterize all hardcoded NFS and site-specific references |
| 3 | [pr3-volsync-s3.md](pr3-volsync-s3.md) | Migrate Volsync from Kopia-filesystem (NFS) to Kopia-S3 (Garage) |
| 4 | [pr4-garage-local-storage.md](pr4-garage-local-storage.md) | Make Garage storage independent per cluster |
| 5 | [pr5-garage-replication.md](pr5-garage-replication.md) | Set up Garage cross-site replication |
| 6 | [pr6-fix-failover.md](pr6-fix-failover.md) | Fix failover — actually stop workloads on standby clusters |
