# Special Winner

A Kubernetes homelab cluster deployed with [Talos Linux](https://www.talos.dev/) and [Flux CD](https://fluxcd.io/) for GitOps-driven infrastructure management.

Built on the [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template), this cluster uses [makejinja](https://github.com/mirkolenz/makejinja) for configuration templating and delivers a fully declarative, Git-managed infrastructure.

## At a Glance

| Component | Technology | Version |
|-----------|-----------|---------|
| OS | Talos Linux | 1.13.0 |
| Orchestration | Kubernetes | 1.35.4 |
| GitOps | Flux CD | 2.8.6 |
| CNI | Cilium | 1.19.3 |
| Ingress | Envoy Gateway | v1.7.2 |
| Secrets | SOPS + Age | 3.13.0 / 1.3.1 |
| Identity | Kanidm | SSO/OAuth2 |
| Packages | Helm | 4.1.4 (v4) |
| Database | CloudNative-PG | PostgreSQL 17.7 |
| Virtualization | KubeVirt | 1.7.0 |

## What's Deployed

**60+ applications** across **17 namespaces** covering:

- **Media** -- Plex, Radarr, Sonarr, Prowlarr, Bazarr, qBittorrent, and more
- **Virtualization** -- KubeVirt with Debian, Ubuntu, and Windows VMs
- **Identity** -- Kanidm SSO with OAuth2 integrations
- **Observability** -- Prometheus, Grafana, Victoria Logs, Gatus, OpenCost, TeslaMate
- **Databases** -- PostgreSQL 17.7 HA cluster (3 instances) + MariaDB 11.7 Galera + Dragonfly
- **Networking** -- Cilium, Envoy Gateway, Cloudflare Tunnel, Multus, Macvtap
- **Storage** -- OpenEBS, VolSync, Garage S3, NFS
- **CI/CD** -- GitHub Actions runners, Forgejo with CI runners
- **Utilities** -- Plane, Homepage, Forgejo, SMTP relay, and more

## Quick Links

- [Getting Started](getting-started/index.md) -- Set up the cluster from scratch
- [Architecture](architecture.md) -- Understand how everything fits together
- [Applications](applications/index.md) -- Browse deployed applications
- [Operations](operations/index.md) -- Day-2 operations and troubleshooting
- [Development](development/index.md) -- Template system and CI/CD
