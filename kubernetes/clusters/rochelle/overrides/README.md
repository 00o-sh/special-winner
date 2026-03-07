# Rochelle Cluster Overrides

This directory contains cluster-specific patches for the rochelle (standby) cluster.
These patches modify the shared base manifests in `kubernetes/apps/` for rochelle's
specific requirements.

## databases/cnpg-standby-patch.yaml

Converts the CNPG PostgreSQL cluster from a standalone primary into a streaming
replica that follows the 3226 primary cluster. This ensures rochelle has an
up-to-date copy of all databases for instant promotion during failover.

### Promotion Procedure

When promoting rochelle to active:

1. Change `cluster_role` to `active` in `kubernetes/clusters/rochelle/flux/ks.yaml`
2. Remove or disable the CNPG standby patch (the cluster becomes a standalone primary)
3. Change 3226's `cluster_role` to `standby`
4. Push changes — Flux handles the rest

### Prerequisites (TODO)

- [ ] Cross-cluster networking (Cloudflare Tunnel or WireGuard)
- [ ] TLS certificates for streaming replication
- [ ] `streaming_replica` user on 3226 primary
- [ ] pg_hba.conf entry on 3226 for rochelle connections
