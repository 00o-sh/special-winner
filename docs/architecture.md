# Architecture

## High-Level Overview

```mermaid
graph TB
    subgraph Internet
        CF[Cloudflare Tunnel]
    end

    subgraph Cluster["Kubernetes Cluster (Talos Linux)"]
        subgraph GitOps["GitOps Layer"]
            Flux[Flux CD]
            Git[GitHub Repository]
        end

        subgraph Networking["Networking Layer"]
            Cilium[Cilium CNI]
            Envoy[Envoy Gateway]
            DNS[CoreDNS + k8s_gateway]
            Multus[Multus CNI]
        end

        subgraph Identity["Identity Layer"]
            Kanidm[Kanidm SSO]
        end

        subgraph Data["Data Layer"]
            PG[CloudNative-PG]
            Dragonfly[Dragonfly]
            OpenEBS[OpenEBS]
            NFS[NFS Storage]
        end

        subgraph Apps["Application Layer"]
            Media[Media Stack]
            VMs[KubeVirt VMs]
            Utils[Utilities]
            Obs[Observability]
        end

        subgraph Security["Security Layer"]
            SOPS[SOPS + Age]
            ExtSec[External Secrets]
            CertMgr[cert-manager]
            kGuardian[kGuardian]
        end
    end

    CF --> Envoy
    Git --> Flux
    Flux --> Apps
    Flux --> Networking
    Flux --> Data
    Flux --> Security
    Envoy --> Apps
    Kanidm --> Apps
    PG --> Apps
    Cilium --> Envoy
    Multus --> VMs
```

## GitOps Flow

All cluster state is defined in Git. Changes flow through this pipeline:

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as GitHub
    participant Flux as Flux CD
    participant K8s as Kubernetes

    Dev->>Git: Push manifests
    Git->>Flux: Webhook / Poll
    Flux->>Flux: Reconcile Kustomizations
    Flux->>K8s: Apply HelmReleases
    K8s->>K8s: Deploy workloads
    Flux->>Git: Update status
```

## Directory Layout

```
special-winner/
├── .github/workflows/     # CI/CD pipelines
├── .taskfiles/            # Task automation (bootstrap, talos, template, vm)
├── bootstrap/             # Initial cluster bootstrap (Helmfile, SOPS secrets)
├── kubernetes/
│   ├── apps/              # Application manifests (17 namespaces)
│   ├── components/        # Shared components (alerts, nfs-scaler, volsync, sops)
│   └── flux/              # Flux configuration (root Kustomization)
├── talos/                 # Talos Linux config and patches
├── templates/             # Jinja2 templates for config generation
├── scripts/               # Bootstrap and utility scripts
├── docs/                  # This documentation
├── mkdocs.yml             # Documentation site config
├── Taskfile.yaml          # Root task runner
├── .mise.toml             # Development tool versions
├── .sops.yaml             # SOPS encryption rules
└── makejinja.toml         # Template rendering config
```

## Application Structure

Every application follows a consistent pattern:

```
kubernetes/apps/<namespace>/<app-name>/
├── app/
│   ├── helmrelease.yaml       # Helm chart deployment
│   ├── ocirepository.yaml     # OCI chart source
│   ├── secret.sops.yaml       # Encrypted secrets (if needed)
│   └── kustomization.yaml     # Manifest aggregation
└── ks.yaml                    # Flux Kustomization
```

## Namespace Map

| Namespace | Purpose | Key Apps |
|-----------|---------|----------|
| `actions-runner-system` | CI/CD runners | Actions Runner Controller |
| `cert-manager` | TLS certificates | cert-manager |
| `database` | Database services | CloudNative-PG, Dragonfly, DBGate |
| `default` | Test workloads | echo |
| `external-secrets` | Secret management | External Secrets, 1Password |
| `flux-system` | GitOps | Flux Operator, Flux Instance |
| `forgejo-runner-system` | Forgejo CI/CD | Forgejo Runner (ScaledJob) |
| `identity` | SSO/Identity | Kanidm (OAuth2 for 5+ apps) |
| `kube-system` | Core services | Cilium, CoreDNS, Spegel, kGuardian |
| `kubevirt` | Virtualization | KubeVirt, CDI, VMs |
| `media` | Media apps | Plex, *arr stack, qBittorrent |
| `network` | Network infra | Envoy Gateway, Error Pages, Cloudflare, Multus |
| `observability` | Monitoring | Prometheus, Grafana, Victoria Logs |
| `openebs-system` | Block storage | OpenEBS |
| `system-upgrade` | Upgrades | Tuppr |
| `utils` | Utilities | Forgejo, Homepage, Penpot, SMTP |
| `volsync-system` | Backups | VolSync, Garage, Kopia |

## Network Architecture

- **Cilium** provides eBPF-based CNI with advanced network policies
- **Envoy Gateway** handles HTTP routing with internal and external gateways, with custom error pages via responseOverride redirects
- **Cloudflare Tunnel** provides secure external access without port forwarding
- **Multus + Macvtap** gives VMs direct network access with dedicated MAC addresses
- **k8s_gateway** provides split-horizon DNS for internal service resolution

## Storage Architecture

| Storage Class | Backend | Use Case |
|---------------|---------|----------|
| `openebs-hostpath` | OpenEBS | Database volumes, high-performance local |
| `nfs-fast` | CSI Driver NFS | VM disks, shared media, ReadWriteMany |
| Garage S3 | Garage | Backup destination for VolSync/Kopia |

## Secret Flow

```mermaid
graph LR
    A[1Password] -->|ExternalSecrets| B[Kubernetes Secrets]
    C[age.key] -->|SOPS| D[Encrypted YAML in Git]
    D -->|Flux Decryption| B
    B --> E[Applications]
```

- **SOPS + Age**: Encrypts secrets in Git (`*.sops.yaml` files)
- **External Secrets Operator**: Pulls secrets from 1Password at runtime
- **Flux**: Automatically decrypts SOPS secrets during reconciliation
