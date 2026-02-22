# Special Winner

A Kubernetes homelab cluster deployed with [Talos Linux](https://www.talos.dev/) and [Flux CD](https://fluxcd.io/) for GitOps-driven infrastructure management.

Built on the [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template), this cluster uses [makejinja](https://github.com/mirkolenz/makejinja) for configuration templating and delivers a fully declarative, Git-managed infrastructure.

## At a Glance

| Component | Technology | Version |
|-----------|-----------|---------|
| OS | Talos Linux | 1.12.4 |
| Orchestration | Kubernetes | 1.34.0 |
| GitOps | Flux CD | 2.7.5 |
| CNI | Cilium | 1.19.0 |
| Ingress | Envoy Gateway | v1.6.3 |
| Secrets | SOPS + Age | 3.11.0 / 1.3.1 |
| Identity | Kanidm | SSO/OAuth2 |
| Packages | Helm | 4.1.1 (v4) |
| Database | CloudNative-PG | PostgreSQL 17.7 |
| Virtualization | KubeVirt | 1.7.0 |

## What's Deployed

**65+ applications** across **17 namespaces** covering:

- **Media** -- Plex, Radarr, Sonarr, Prowlarr, Bazarr, qBittorrent, and more
- **Virtualization** -- KubeVirt with Debian, Ubuntu, Windows, and FreePBX VMs
- **Identity** -- Kanidm SSO with OAuth2 integrations
- **Observability** -- Prometheus, Grafana, Victoria Logs, Gatus, OpenCost
- **Databases** -- PostgreSQL 17.7 HA cluster (3 instances) + Dragonfly
- **Networking** -- Cilium, Envoy Gateway, Cloudflare Tunnel, Multus
- **Storage** -- OpenEBS, VolSync, Garage S3, NFS
- **CI/CD** -- GitHub Actions runners, Forgejo with CI runners
- **Networking** -- LibreSpeed multi-path speed test
- **Utilities** -- Penpot, Homepage, SMTP relay, and more

## Quick Links

- [Getting Started](getting-started/index.md) -- Set up the cluster from scratch
- [Architecture](architecture.md) -- Understand how everything fits together
- [Applications](applications/index.md) -- Browse deployed applications
- [Operations](operations/index.md) -- Day-2 operations and troubleshooting
- [Development](development/index.md) -- Template system and CI/CD
