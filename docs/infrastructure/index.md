# Infrastructure

This section covers the core infrastructure components that power the cluster.

## Component Overview

```mermaid
graph LR
    subgraph OS["Operating System"]
        Talos[Talos Linux 1.12.4]
    end
    subgraph Network["Networking"]
        Cilium[Cilium 1.19.0]
        Envoy[Envoy Gateway v1.6.3]
        CF[Cloudflare Tunnel]
    end
    subgraph Data["Data"]
        PG[PostgreSQL 17.7]
        MDB[MariaDB 11.7 Galera]
        DF[Dragonfly]
        OEBS[OpenEBS]
    end
    subgraph GitOps
        Flux[Flux CD 2.7.5]
    end
    subgraph Security
        SOPS[SOPS + Age]
        Kanidm[Kanidm SSO]
        CM[cert-manager]
    end

    Talos --> Cilium
    Cilium --> Envoy
    Flux --> Network
    Flux --> Data
    Flux --> Security
```

## Pages

| Page | Description |
|------|-------------|
| [Talos Linux](talos.md) | Immutable Kubernetes OS configuration and management |
| [Flux CD](flux.md) | GitOps continuous delivery |
| [Cilium](cilium.md) | eBPF-based container networking |
| [Envoy Gateway](envoy-gateway.md) | HTTP routing and ingress |
| [Storage](storage.md) | OpenEBS, NFS, and backup systems |
| [Databases](databases.md) | PostgreSQL HA, MariaDB Galera, and Dragonfly |
| [Certificates & DNS](certificates-dns.md) | TLS automation and DNS management |
| [Secrets](secrets.md) | SOPS, Age, and External Secrets |
| [Identity & SSO](identity.md) | Kanidm identity provider |
