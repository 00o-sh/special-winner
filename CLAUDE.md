# CLAUDE.md - AI Assistant Guide

This document provides comprehensive guidance for AI assistants working with this Kubernetes cluster template repository.

## Project Overview

**Repository**: Kubernetes Cluster Template (based on onedr0p/cluster-template)
**Purpose**: Template-driven Kubernetes cluster deployment framework for home-ops/homelab environments
**Architecture**: GitOps-based infrastructure-as-code using Talos Linux, Flux CD, and Jinja2 templating

### Core Components

- **OS**: Talos Linux 1.12.1 (immutable Kubernetes OS)
- **Orchestration**: Kubernetes 1.34.0
- **GitOps**: Flux CD 2.7.5 (declarative continuous delivery)
- **CNI**: Cilium 1.19.0 (eBPF-based networking)
- **Ingress**: Envoy Gateway (HTTP routing)
- **Secrets**: SOPS 3.11.0 + Age 1.3.1 encryption
- **DNS**: k8s_gateway + CoreDNS + External-DNS
- **Certificates**: cert-manager with Cloudflare integration
- **Package Management**: Helm 4.0.5 (Helm v4 for chart management)

## Directory Structure

```
special-winner/
├── .github/                          # GitHub Actions & CI/CD
│   ├── workflows/                    # CI/CD pipelines
│   │   ├── e2e.yaml                 # End-to-end testing
│   │   ├── flux-local.yaml          # Flux validation
│   │   └── ...
│   └── tests/                        # Test configuration samples
│
├── .taskfiles/                       # Task automation definitions
│   ├── bootstrap/Taskfile.yaml       # Bootstrap tasks
│   ├── talos/Taskfile.yaml          # Talos operations
│   └── template/Taskfile.yaml       # Template rendering
│
├── bootstrap/                        # Initial cluster bootstrap
│   ├── helmfile.d/                  # Helm releases
│   │   ├── 00-crds.yaml            # CRD extraction
│   │   └── 01-apps.yaml            # Bootstrap apps
│   ├── github-deploy-key.sops.yaml  # Encrypted deploy key
│   ├── onepassword-secret.sops.yaml # 1Password credentials
│   └── sops-age.sops.yaml          # Age encryption key
│
├── kubernetes/                       # Kubernetes manifests
│   ├── apps/                        # Application deployments
│   │   ├── <namespace>/            # One dir per namespace
│   │   │   ├── <app-name>/        # One dir per app
│   │   │   │   ├── app/           # App manifests
│   │   │   │   │   ├── helmrelease.yaml
│   │   │   │   │   ├── ocirepository.yaml
│   │   │   │   │   ├── secret.sops.yaml
│   │   │   │   │   └── kustomization.yaml
│   │   │   │   └── ks.yaml        # Flux Kustomization
│   │   │   ├── namespace.yaml
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml
│   ├── components/                  # Shared components
│   │   ├── alerts/                 # Prometheus alerts & integrations
│   │   │   ├── alertmanager/      # AlertManager configuration
│   │   │   ├── discord/           # Discord webhook integration
│   │   │   └── github-status/     # GitHub status updates
│   │   ├── nfs-scaler/            # KEDA-based NFS scaling
│   │   ├── sops/                  # SOPS integration
│   │   └── volsync/               # Backup config
│   └── flux/                        # Flux configuration
│       └── cluster/ks.yaml         # Root Kustomization
│
├── talos/                           # Talos Linux config
│   ├── clusterconfig/              # Generated configs (gitignored)
│   └── patches/                    # Config patches
│       ├── global/                # All nodes
│       ├── controller/            # Controller-specific
│       ├── worker/                # Worker-specific
│       └── ${node-hostname}/      # Per-node
│
├── templates/                       # Jinja2 templates
│   ├── config/                     # Config templates
│   ├── overrides/                 # Output overrides
│   └── scripts/                   # Custom Jinja2 filters
│       └── plugin.py              # Custom functions
│
├── scripts/                         # Utility scripts
│   ├── bootstrap-apps.sh           # Main bootstrap script
│   └── lib/common.sh               # Shared utilities
│
├── .mise.toml                       # Development tools config
├── .sops.yaml                      # SOPS encryption config
├── makejinja.toml                 # Template rendering config
├── Taskfile.yaml                  # Root task definitions
└── README.md                        # User documentation
```

## Key Configuration Files

### Development Environment

**`.mise.toml`** - Defines all required CLI tools and versions
- Manages Python, Go, and specialized Kubernetes tools
- Creates reproducible dev environment via `mise install`
- Sets environment variables: KUBECONFIG, SOPS_AGE_KEY_FILE, TALOSCONFIG

**`Taskfile.yaml`** - Main task automation entry point
- Includes subtasks from `.taskfiles/`
- Core tasks: `reconcile`, `bootstrap:talos`, `bootstrap:apps`, `template:configure`

### Template System

**`makejinja.toml`** - Template rendering configuration
```toml
inputs = ["./templates/overrides","./templates/config"]
output = "./"
data = ["./cluster.yaml", "./nodes.yaml"]
import_paths = ["./templates/scripts"]
```

**Custom Jinja2 Delimiters**: Uses `#{...}#` instead of `{{...}}` to avoid YAML conflicts
- Variables: `#{ variable }#`
- Blocks: `#% if condition %# ... #% endif %#`
- Comments: `#| comment #|`

### Secret Management

**`.sops.yaml`** - Encryption configuration
- Talos configs: `talos/.*\.sops\.ya?ml` (full file encryption)
- Kubernetes secrets: `(bootstrap|kubernetes)/.*\.sops\.ya?ml` (encrypted_regex: "^(data|stringData)$")
- Uses Age encryption with public key: `age17a9gk8fq0rz9utn3jzhtc2nqvypk996cj5eamuw75j73uphvsursv37973`

## Development Workflows

### Initial Setup

1. **Install development tools**:
   ```bash
   mise trust
   pip install pipx
   mise install
   ```

2. **Initialize configuration**:
   ```bash
   task init  # Creates cluster.yaml, nodes.yaml, age.key, etc.
   ```

3. **Configure and validate**:
   ```bash
   task configure  # Renders templates and validates configs
   ```

4. **Bootstrap cluster**:
   ```bash
   task bootstrap:talos  # Install Talos on nodes
   task bootstrap:apps   # Install Flux and core apps
   ```

### Day-2 Operations

**Force Flux reconciliation**:
```bash
task reconcile
```

**Update Talos configuration**:
```bash
task talos:generate-config
task talos:apply-node IP=10.10.10.10 MODE=auto
```

**Upgrade Talos version**:
```bash
task talos:upgrade-node IP=10.10.10.10
```

**Upgrade Kubernetes version**:
```bash
task talos:upgrade-k8s
```

**Reset cluster**:
```bash
task talos:reset  # WARNING: Destructive operation
```

### Debugging

**Check Flux status**:
```bash
flux check
flux get sources git -A
flux get ks -A  # Kustomizations
flux get hr -A  # HelmReleases
```

**Check Cilium networking**:
```bash
cilium status
```

**Inspect pod logs**:
```bash
kubectl -n <namespace> get pods
kubectl -n <namespace> logs <pod-name> -f
kubectl -n <namespace> describe pod <pod-name>
```

**View namespace events**:
```bash
kubectl -n <namespace> get events --sort-by='.metadata.creationTimestamp'
```

## Kubernetes Manifest Patterns

### Application Directory Structure

Each application follows this pattern:
```
apps/<namespace>/<app-name>/
├── app/
│   ├── helmrelease.yaml       # Helm chart reference
│   ├── ocirepository.yaml     # OCI chart source
│   ├── secret.sops.yaml       # Encrypted secrets
│   └── kustomization.yaml     # Manifest aggregation
└── ks.yaml                    # Flux Kustomization
```

### HelmRelease Pattern

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app-name>
spec:
  chartRef:
    kind: OCIRepository
    name: <chart-name>
  interval: 1h
  values:
    image:
      repository: ghcr.io/owner/app
      tag: v1.2.3  # Updated by Renovate
    resources:
      requests:
        cpu: 10m
        memory: 64Mi
      limits:
        memory: 256Mi
    probes:
      liveness: &probes
        enabled: true
        custom: true
        spec:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 0
          periodSeconds: 10
      readiness: *probes
```

### Flux Kustomization Pattern

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app-name>
spec:
  interval: 1h
  path: ./kubernetes/apps/<namespace>/<app>/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: <namespace>
  wait: false
```

### Namespace Pattern

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: <namespace-name>
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

## Bash Script Conventions

Scripts in `scripts/` follow these patterns:

### Standard Header

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
export ROOT_DIR="$(git rev-parse --show-toplevel)"
```

### Logging

```bash
log debug "Debug message"
log info "Information message" "var=value"
log warn "Warning message"
log error "Error message"  # Exits with code 1
```

### Environment Checks

```bash
check_env KUBECONFIG TALOSCONFIG  # Verify env vars
check_cli kubectl flux sops       # Verify CLI tools
```

## Git Commit Conventions

This repository uses **semantic commits** with Renovate conventions:

```
<type>(<scope>): <message>

Types:
- feat: New feature
- fix: Bug fix
- chore: Maintenance
- ci: CI/CD changes
- docs: Documentation
- refactor: Code refactoring

Scopes (Common):
- container: Docker images
- helm: Helm charts
- github-action: GitHub Actions
- kubernetes: Kubernetes manifests
- observability: Monitoring and alerting
- volsync: Backup and replication
- github: GitHub configuration
- mise: Development tools
- media: Media applications
- network: Network infrastructure
- utils: Utility services

Examples:
- fix(container): update image ghcr.io/app/name ( 1.0.0 → 1.1.0 )
- feat(helm): update chart app-template ( 3.0.0 → 4.0.0 )
- ci(github-action): update action/checkout ( v3 → v4 )
- chore(observability): disable buddy heartbeat monitor and alerts
- fix(volsync): change backup schedule from every 5 minutes to daily at 2 AM
```

## AI Assistant Guidelines

### When Making Changes

1. **Always read files before modifying** - Never propose changes to code you haven't read
2. **Understand existing patterns** - Follow the established directory structure and naming conventions
3. **Use appropriate tools**:
   - Use `Read` for reading files, not `cat`
   - Use `Edit` for modifying files, not `sed`
   - Use `Grep` for searching content, not `grep`
   - Use `Glob` for finding files, not `find`
4. **Test configurations** before committing:
   ```bash
   task template:validate-kubernetes-config
   task template:validate-talos-config
   ```

### Adding New Applications

When adding a new Kubernetes application:

1. **Create directory structure**:
   ```bash
   kubernetes/apps/<namespace>/<app-name>/app/
   ```

2. **Create required files**:
   - `helmrelease.yaml` - Helm chart deployment
   - `ocirepository.yaml` - Chart source
   - `kustomization.yaml` - Manifest aggregation
   - `secret.sops.yaml` - Encrypted secrets (if needed)

3. **Create Flux Kustomization**:
   - `ks.yaml` in the app directory

4. **Update namespace kustomization**:
   - Add reference to new `ks.yaml` in `kubernetes/apps/<namespace>/kustomization.yaml`

5. **Encrypt secrets**:
   ```bash
   sops --encrypt --in-place kubernetes/apps/<namespace>/<app-name>/app/secret.sops.yaml
   ```

### Security Considerations

1. **Never commit unencrypted secrets** - All sensitive data must be in `*.sops.yaml` files
2. **Validate encryption** - Check that `*.sops.yaml` files contain `sops:` metadata
3. **Follow security contexts**:
   ```yaml
   securityContext:
     allowPrivilegeEscalation: false
     readOnlyRootFilesystem: true
     capabilities: { drop: ["ALL"] }
   ```

### Common Mistakes to Avoid

1. **Don't modify generated files** - Files in `talos/clusterconfig/` are generated, modify source templates instead
2. **Don't commit plaintext secrets** - Always use SOPS encryption
3. **Don't skip validation** - Always run `task configure` after template changes
4. **Don't push directly to main** - Development should happen on feature branches
5. **Don't add unnecessary complexity** - Follow the principle of minimal necessary changes
6. **Don't add comments/docstrings** to code you didn't modify
7. **Don't create abstractions** for one-time operations
8. **Be aware of Helm v4** - The repository uses Helm 4.0.5, which has breaking changes from v3 (see bootstrap scripts)
9. **Self-hosted runners** - Be aware that some workflows run on `special-winner-runner` (self-hosted) which has cluster access

### File Location Reference

**Need to modify Talos configuration?**
→ Edit templates: `templates/config/talos/talconfig.yaml.j2`
→ Edit patches: `talos/patches/global/*.yaml.j2`
→ Then run: `task talos:generate-config`

**Need to modify Kubernetes apps?**
→ Edit manifests: `kubernetes/apps/<namespace>/<app>/app/*.yaml`
→ Use Flux for automatic sync or: `task reconcile`

**Need to modify bootstrap process?**
→ Edit: `scripts/bootstrap-apps.sh`
→ Edit: `bootstrap/helmfile.d/*.yaml`

**Need to change cluster-wide settings?**
→ Edit: `cluster.yaml` (if it exists)
→ Then run: `task configure`

**Need to add/modify nodes?**
→ Edit: `nodes.yaml` (if it exists)
→ Then run: `task configure`

## Important Commands Reference

| Task | Command |
|------|---------|
| List all tasks | `task --list` |
| Initialize config | `task init` |
| Validate & render | `task configure` |
| Bootstrap Talos | `task bootstrap:talos` |
| Bootstrap apps | `task bootstrap:apps` |
| Force Flux sync | `task reconcile` |
| Generate Talos config | `task talos:generate-config` |
| Apply config to node | `task talos:apply-node IP=<ip> MODE=auto` |
| Upgrade Talos | `task talos:upgrade-node IP=<ip>` |
| Upgrade Kubernetes | `task talos:upgrade-k8s` |
| Reset cluster | `task talos:reset` |
| Validate K8s manifests | `task template:validate-kubernetes-config` |
| Tidy templates | `task template:tidy` |

## Renovate Automation

This repository uses Renovate for automatic dependency updates:

- **Schedule**: Every weekend (configurable in `.renovaterc.json5`)
- **Auto-merge**: GitHub Actions (minor/patch), Mise tools (minor/patch)
- **Manual review**: Helm charts, Container images (major versions)
- **Semantic commits**: Automatically formatted with type and scope
- **Configuration**: `.renovaterc.json5`

Renovate creates a "Dependency Dashboard" issue with checkboxes for manual control.

## CI/CD Pipelines

### flux-local.yaml
Validates Flux manifests on pull requests:
- Checks Flux configuration with `--enable-helm --all-namespaces`
- Generates diffs for HelmReleases and Kustomizations
- Runs only when `kubernetes/**` files change

### e2e.yaml
Tests complete configuration pipeline:
- Runs `task init` and `task configure`
- Tests with sample configurations (public/private)
- Validates with flux-local
- Matrix: public and private configurations

### labeler.yaml
Automated PR labeling workflow:
- Labels PRs based on changed file paths (area labels)
- Labels PRs based on size (xs/s/m/l/xl)
- Uses `.github/labeler.yaml` for path-based rules
- Size thresholds: xs(<10), s(<30), m(<100), l(<500), xl(500+)
- Ignores markdown and documentation files for size calculation

### label-sync.yaml
Synchronizes GitHub repository labels:
- Triggered on pushes to main when `.github/labels.yaml` changes
- Syncs labels defined in `.github/labels.yaml`
- Deletes labels not defined in configuration
- Maintains consistent labeling across the repository

### release.yaml
Handles repository releases (if applicable)

### image-pull.yaml
Automated container image pre-pulling workflow:
- Extracts images from Flux manifests on PRs
- Compares images between PR and main branch
- Automatically pulls new images to cluster nodes using Talosctl
- Runs on self-hosted runner (special-winner-runner)
- Prevents image pull delays during deployments
- Max parallel pulls: 4

### schemas.yaml
CRD schema extraction and publishing:
- Scheduled daily and on workflow changes
- Extracts Kubernetes CRD schemas using datreeio/crd-extractor
- Publishes schemas to Cloudflare Pages (kubernetes-schemas project)
- Runs on self-hosted runner (special-winner-runner)
- Uses Python 3.14 and Node 24.x for processing
- Enables IDE autocompletion and validation for custom resources

## Template System Details

### Custom Jinja2 Filters

Located in `templates/scripts/plugin.py`:

```python
nthhost(cidr, index)      # Get Nth host in CIDR range
age_key(key_type)         # Extract age public/private key
basename(path)            # Get filename without extension
```

Usage in templates:
```jinja2
#{ "10.0.0.0/24" | nthhost(1) }#  → "10.0.0.1"
#{ "public" | age_key }#          → Returns public key
#{ "path/to/file.txt" | basename }#  → "file"
```

### Configuration Files

Templates read from:
- `cluster.yaml` - Cluster-wide configuration
- `nodes.yaml` - Node definitions

These files are generated from samples via `task init` and are gitignored.

## Troubleshooting

### Templates not rendering
```bash
task template:validate-schemas  # Check cluster.yaml & nodes.yaml
task template:render-configs    # Force re-render
```

### Secrets not decrypting
```bash
# Verify age key exists
test -f age.key && echo "Key exists" || echo "Missing key"

# Verify SOPS can decrypt
sops --decrypt bootstrap/sops-age.sops.yaml
```

### Flux not syncing
```bash
flux check                    # Check Flux health
flux logs --all-namespaces   # View Flux logs
task reconcile               # Force sync
```

### Nodes not joining cluster
```bash
talosctl get members --nodes <ip> --insecure
talosctl logs --nodes <ip> --insecure
```

## Deployed Applications

### Current Namespaces and Applications

**actions-runner-system**: GitHub Actions Infrastructure
- actions-runner-controller (self-hosted runner controller)

**cert-manager**: Certificate management
- cert-manager

**default**: Default namespace
- echo (test application)

**external-secrets**: Secret management
- discord-webhook (Discord integration)
- external-secrets (operator)
- onepassword (1Password integration)

**flux-system**: GitOps
- flux-instance
- flux-operator

**kube-system**: Core Kubernetes
- cilium (CNI)
- coredns (DNS)
- csi-driver-nfs (NFS storage)
- metrics-server
- reloader (automatic pod restarts)
- snapshot-controller (volume snapshots)

**media**: Media applications
- autobrr (automation for torrent trackers)
- bazarr (subtitle management)
- flaresolverr (Cloudflare bypass for web scraping)
- plex (media server)
- prowlarr (indexer manager)
- qbittorrent (torrent client)
- qui (qBittorrent web UI)
- radarr (movie collection manager)
- recyclarr (quality profile management for *arr apps)
- seerr (media request and discovery)
- sonarr (TV series collection manager)
- tautulli (Plex monitoring and statistics)
- thelounge (IRC client)

**network**: Network infrastructure
- cloudflare-dns
- cloudflare-tunnel (external access)
- envoy-gateway (ingress)
- k8s-gateway (internal DNS)
- multus (multi-network CNI)
- unifi-dns

**observability**: Monitoring and alerting
- blackbox-exporter (endpoint monitoring)
- fluent-bit (log forwarding)
- gatus (health checks and uptime monitoring)
- grafana (metrics visualization)
- keda (event-driven autoscaling)
- kromgo (custom metrics)
- kube-prometheus-stack (Prometheus, AlertManager, Grafana)
- silence-operator (alert silencing)
- victoria-logs (log aggregation)

**openebs-system**: Storage
- openebs (cloud-native storage)

**system-upgrade**: System management
- tuppr (automated upgrades)

**utils**: Utility services
- smtp-relay (SMTP relay for outbound email using Maddy)

**volsync-system**: Backup and replication
- garage (S3-compatible storage backend)
- kopia (backup repository)
- volsync (volume replication)

## Additional Resources

- **Official Docs**: See README.md for detailed user documentation
- **Community**: GitHub Discussions and Discord (Home Operations)
- **Related Tools**:
  - [Talos Linux](https://www.talos.dev/)
  - [Flux CD](https://fluxcd.io/)
  - [Cilium](https://cilium.io/)
  - [SOPS](https://github.com/getsops/sops)
  - [Helm](https://helm.sh/) (Note: Using v4)

## Version Information

This documentation applies to:
- Talos Linux: 1.12.1
- Kubernetes: 1.34.0
- Flux CD: 2.7.5
- Cilium: 1.19.0
- Helm: 4.0.5

Check `.mise.toml` for exact versions of all tools.

## Recent Notable Changes

- **2026-01-21**: Added GitHub Actions self-hosted runner system (actions-runner-system namespace)
- **2026-01-21**: Added SMTP relay service for outbound email (utils namespace with Maddy)
- **2026-01-21**: New CI/CD workflows for automated image pulling and CRD schema publishing
- **2026-01-21**: Helm version updated from 4.0.4 to 4.0.5
- **2026-01-15**: Expanded media stack with Radarr, Sonarr, Seerr, Recyclarr, Tautulli, FlareSolverr, TheLounge
- **2026-01-09**: Buddy heartbeat monitoring disabled in observability stack
- **2026-01-09**: Added comprehensive GitHub label automation (labeler and label-sync workflows)
- **2026-01-08**: Multiple media applications added (Plex, Bazarr, Autobrr, Prowlarr, qBittorrent)
- **2026-01-08**: Volsync backup schedule changed from every 5 minutes to daily at 2 AM
- **2026-01-08**: Discord webhook integration added to AlertManager
- **2026-01-08**: NFS-scaler component added using KEDA for smart scaling

## Component Deep Dives

### GitHub Actions Self-Hosted Runner System

Located in `kubernetes/apps/actions-runner-system/`, this system provides self-hosted GitHub Actions runners within the Kubernetes cluster.

**Components**:
- **actions-runner-controller**: Manages GitHub Actions Runner Scale Sets
- **runners**: Ephemeral runner pods that execute GitHub Actions workflows

**How it works**:
- Uses GitHub's official Actions Runner Controller (ARC) architecture
- Creates on-demand runner pods for workflow jobs
- Scales based on GitHub webhook events
- Provides isolated execution environment with cluster access
- Used by workflows like `image-pull.yaml` and `schemas.yaml` that need cluster access

**Benefits**:
- Access to internal cluster resources (Talosctl for image pulling)
- Faster job execution (no cold start, local image cache)
- Cost savings (no GitHub-hosted runner minutes)
- Custom runner configurations and tools

**Configuration**: Runner scale sets are defined in `kubernetes/apps/actions-runner-system/actions-runner-controller/runners/`

### SMTP Relay Service

Located in `kubernetes/apps/utils/smtp-relay/`, this service provides a centralized SMTP relay for outbound email from cluster applications.

**How it works**:
- Uses Maddy mail server (lightweight, modern SMTP server)
- Accepts email on port 25 via LoadBalancer service (10.0.6.15)
- Relays through external SMTP provider (configured via secrets)
- Supports STARTTLS and authentication
- Hostname: smtp-relay.00o.sh (via external-dns)

**Configuration**:
- SMTP relay credentials stored in encrypted secrets
- Config file mounted from ConfigMap
- State and runtime data stored in emptyDir
- Single replica with RollingUpdate strategy
- Auto-reloads on secret changes (via Reloader)

**Security**:
- Non-root user (UID/GID 1000)
- Read-only root filesystem
- No privilege escalation
- All capabilities dropped

**Usage**: Applications can send email to `smtp-relay.utils.svc.cluster.local:25` or via the LoadBalancer IP.

### NFS Scaler Component

Located in `kubernetes/components/nfs-scaler/`, this component uses KEDA (Kubernetes Event Driven Autoscaling) to intelligently scale applications that depend on NFS storage.

**How it works**:
- Uses a KEDA ScaledObject to monitor NFS availability
- Queries Prometheus for `probe_success{instance=~".+:2049"}` metric
- Scales deployments from 0 to 1 replica when NFS is available
- Scales down to 0 when NFS is unavailable
- Prevents pods from crash-looping when NFS mount points are down

**Usage**: Apply this component to applications that mount NFS volumes and should only run when NFS is healthy.

### Alerts Component Structure

The `kubernetes/components/alerts/` directory contains:
- **alertmanager/**: AlertManager configuration and routing rules
- **discord/**: Discord webhook integration for notifications
- **github-status/**: GitHub status update integration

This modular approach allows different notification channels to be enabled/disabled independently.

### GitHub Label System

The repository uses an automated label management system:

**Label Categories**:
- `area/*`: Denotes which part of the codebase was changed (bootstrap, kubernetes, talos, etc.)
- `size/*`: Indicates PR size (xs, s, m, l, xl)
- Namespace-specific labels: `area/cert-manager`, `area/media`, `area/observability`, etc.

**Configuration Files**:
- `.github/labels.yaml`: Defines all available labels with colors and descriptions
- `.github/labeler.yaml`: Maps file paths to labels for automatic PR labeling

**Benefits**:
- Consistent labeling across all PRs
- Easy filtering and organization of issues/PRs
- Automatic size warnings for large PRs
- Clear indication of which components are affected by changes

---

**Last Updated**: 2026-01-21
**Template Source**: [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)
