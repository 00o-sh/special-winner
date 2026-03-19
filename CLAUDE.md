# CLAUDE.md - AI Assistant Guide

This document provides comprehensive guidance for AI assistants working with this Kubernetes cluster template repository.

## Project Overview

**Repository**: Kubernetes Cluster Template (based on onedr0p/cluster-template)
**Purpose**: Template-driven Kubernetes cluster deployment framework for home-ops/homelab environments
**Architecture**: GitOps-based infrastructure-as-code using Talos Linux, Flux CD, and Jinja2 templating

### Core Components

- **OS**: Talos Linux 1.12.4 (immutable Kubernetes OS)
- **Orchestration**: Kubernetes 1.34.0
- **GitOps**: Flux CD 2.8.1 (declarative continuous delivery)
- **CNI**: Cilium 1.19.0 (eBPF-based networking)
- **Ingress**: Envoy Gateway v1.6.3 (HTTP routing)
- **Secrets**: SOPS 3.12.1 + Age 1.3.1 encryption
- **Identity**: Kanidm (SSO/OAuth2 identity provider)
- **DNS**: k8s_gateway + CoreDNS + External-DNS
- **Certificates**: cert-manager with Cloudflare integration
- **Package Management**: Helm 4.1.1 (Helm v4 for chart management)
- **Database**: CloudNative-PG (PostgreSQL 17.7) + Dragonfly (Redis-compatible) + MariaDB Operator (MariaDB 11.7 Galera)
- **Virtualization**: KubeVirt 1.7.0 (virtual machine management)
- **External Secrets**: External Secrets Operator 2.0.0 + 1Password Connect (reads) + 1Password SDK (writes)

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
│   ├── template/Taskfile.yaml       # Template rendering
│   └── vm/Taskfile.yaml             # Virtual machine operations
│
├── bootstrap/                        # Initial cluster bootstrap
│   ├── helmfile.d/                  # Helm releases
│   │   ├── 00-crds.yaml            # CRD extraction
│   │   └── 01-apps.yaml            # Bootstrap apps
│   ├── github-deploy-key.sops.yaml  # Encrypted deploy key
│   ├── onepassword-connect-secret.sops.yaml # 1Password Connect credentials
│   ├── onepassword-secret.sops.yaml # 1Password SDK service account token
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
│       ├── vm-node/              # VM-specific (KubeVirt nodes)
│       └── ${node-hostname}/      # Per-node
│
├── templates/                       # Jinja2 templates
│   ├── config/                     # Config templates
│   ├── overrides/                 # Output overrides
│   └── scripts/                   # Custom Jinja2 filters
│       └── plugin.py              # Custom functions
│
├── docs/                            # MkDocs documentation site
│   ├── index.md                    # Home page
│   ├── architecture.md             # Architecture overview
│   ├── getting-started/            # Setup guides
│   ├── infrastructure/             # Infrastructure docs
│   ├── applications/               # Application docs
│   ├── operations/                 # Operations & troubleshooting
│   ├── development/                # Development guides
│   └── research/                   # Research notes
│
├── scripts/                         # Utility scripts
│   ├── bootstrap-apps.sh           # Main bootstrap script
│   ├── generate-labels.sh          # Auto-generate GitHub labels from directory structure
│   ├── volsync-restore-all.sh      # Mass VolSync point-in-time restore for all apps
│   └── lib/common.sh               # Shared utilities
│
├── .mise.toml                       # Development tools config
├── .sops.yaml                      # SOPS encryption config
├── makejinja.toml                 # Template rendering config
├── mkdocs.yml                     # Documentation site config
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

6. **Consider SSO integration** - If the app has a web UI, ask whether Kanidm OAuth2 SSO should be configured (add OAuth2 client definition in `kubernetes/apps/identity/kanidm/app/`)

7. **Add to Homepage dashboard** - New services should be added to the Homepage configuration in `kubernetes/apps/utils/homepage/`

8. **Update documentation** - Update this CLAUDE.md file with the new application entry in the Deployed Applications section

9. **Add Volsync backup config** - Stateful apps with persistent data should include Volsync backup configuration (use `kubernetes/components/volsync/` component)

10. **Add monitoring** - If the app exposes metrics, add ServiceMonitor/PodMonitor and Grafana dashboards when available

11. **Add Discord alert notifications** - Critical applications should have Discord webhook alert integration configured

12. **Add NFS-scaler component** - Applications that mount NFS volumes should use the NFS-scaler component (`kubernetes/components/nfs-scaler/`) to prevent crash-loops when NFS is unavailable

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
8. **Be aware of Helm v4** - The repository uses Helm 4.1.1, which has breaking changes from v3 (see bootstrap scripts)
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
| VM console | `task vm:console VM=<name>` |
| VM start/stop | `task vm:start VM=<name>` / `task vm:stop VM=<name>` |
| Mass VolSync restore | `./scripts/volsync-restore-all.sh` |
| Generate GitHub labels | `./scripts/generate-labels.sh` |
| Build docs locally | `mkdocs build` or `mkdocs serve` |

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

### label-generate.yaml
Generates label configuration from repository structure:
- Automates `.github/labels.yaml` and `.github/labeler.yaml` updates
- Ensures labels stay in sync with namespace and directory changes

### docs.yaml
Documentation site build and publish:
- Builds MkDocs Material site from `docs/` directory
- Publishes to Cloudflare Pages (`special-winner-docs` project)
- Triggered on pushes to main when `docs/**` or `mkdocs.yml` change
- Also supports manual workflow dispatch

### renovate-config.yaml
Renovate configuration validation:
- Validates `.renovaterc.json5` on pull requests
- Runs `renovate-config-validator --strict` to catch config errors
- Only triggers when `.renovaterc.json5` is modified

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
- actions-runner-controller (self-hosted runner controller with scale sets for special-winner and ambersecurityinc orgs)

**cert-manager**: Certificate management
- cert-manager

**database**: Database infrastructure
- cloudnative-pg (PostgreSQL operator + PostgreSQL 17.7 HA cluster with 3 instances)
- dbgate (database management web UI)
- dragonfly (Redis-compatible in-memory datastore operator)
- mariadb-operator (MariaDB operator + MariaDB 11.7 Galera cluster with 3 instances)

**default**: Default namespace
- echo (test application)
- librespeed (multi-path speed test with per-route Envoy tuning)

**external-secrets**: Secret management
- discord-webhook (Discord integration)
- external-secrets (operator)
- onepassword (1Password Connect Server for reads + SDK for writes)

**flux-system**: GitOps
- flux-instance
- flux-operator

**forgejo-runner-system**: Forgejo CI/CD Infrastructure
- forgejo-runner (Forgejo Actions runner with ScaledJob for on-demand scaling)

**identity**: Identity and SSO
- kanidm (identity provider with OAuth2 integrations for dbgate, forgejo, kubevirt-manager, opencost, penpot)

**kube-system**: Core Kubernetes
- cilium (CNI)
- coredns (DNS)
- csi-driver-nfs (NFS storage)
- metrics-server
- reloader (automatic pod restarts)
- snapshot-controller (volume snapshots)
- kguardian (Kubernetes security monitoring and guardian)
- spegel (peer-to-peer container image sharing)

**kubevirt**: Virtual machine infrastructure
- cdi (Containerized Data Importer for VM disk management)
- kubevirt (KubeVirt operator)
- kubevirt-manager (web UI for VM management)
- virtualmachines (VM instances: debian-desktop, debian-server, ubuntu-server, windows-server, freepbx-b1-k3s01, freepbx-b2-k3s01, freepbx-b3-k3s01)

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
- envoy-gateway (ingress, with error-pages for custom error responses)
- k8s-gateway (internal DNS)
- macvtap-cni (macvtap CNI plugin for direct VM network access)
- multus (multi-network CNI)
- unifi-dns
- unifi-toolkit (Unifi network management toolkit)

**observability**: Monitoring and alerting
- blackbox-exporter (endpoint monitoring)
- fluent-bit (log forwarding)
- gatus (health checks and uptime monitoring)
- grafana (metrics visualization)
- keda (event-driven autoscaling)
- kromgo (custom metrics)
- kube-prometheus-stack (Prometheus, AlertManager, Grafana)
- opencost (Kubernetes cost monitoring and analysis)
- silence-operator (alert silencing)
- victoria-logs (log aggregation)

**openebs-system**: Storage
- openebs (cloud-native storage)

**system-upgrade**: System management
- tuppr (automated upgrades)

**ui-bakery**: Low-code platform
- ui-bakery (low-code internal tool builder with MariaDB backend, ExternalSecrets, Envoy Gateway ingress)

**utils**: Utility services
- forgejo (self-hosted Git repository service)
- homepage (cluster dashboard)
- n8n (workflow automation platform)
- penpot (open-source design and prototyping platform)
- smtp-relay (SMTP relay for outbound email using Maddy)

**voip**: VoIP and telephony
- freepbx-b1-k3s01 (containerized FreePBX telephony platform with MariaDB backend)

**zitadel**: External identity provider (SaaS development)
- zitadel (self-hosted Zitadel identity platform at login.00o.sh, network-isolated, PostgreSQL backend, external-only access)

**volsync-system**: Backup and replication
- garage (S3-compatible storage backend)
- kopia (backup repository)
- volsync (volume replication)

## Additional Resources

- **Official Docs**: See [docs.00o.sh](https://docs.00o.sh) for detailed documentation (built from `docs/` directory)
- **Community**: GitHub Discussions and Discord (Home Operations)
- **Related Tools**:
  - [Talos Linux](https://www.talos.dev/)
  - [Flux CD](https://fluxcd.io/)
  - [Cilium](https://cilium.io/)
  - [SOPS](https://github.com/getsops/sops)
  - [Helm](https://helm.sh/) (Note: Using v4)
  - [KubeVirt](https://kubevirt.io/)
  - [Kanidm](https://kanidm.com/) (Identity/SSO)
  - [Forgejo](https://forgejo.org/) (Self-hosted Git)
  - [OpenCost](https://www.opencost.io/) (Cost monitoring)

## Version Information

This documentation applies to:
- Talos Linux: 1.12.4
- Kubernetes: 1.34.0
- Flux CD: 2.8.1
- Cilium: 1.19.0
- Helm: 4.1.1
- Python: 3.14.3
- Envoy Gateway: v1.6.3
- External Secrets: 2.0.0
- CloudNative-PG: PostgreSQL 17.7
- KubeVirt: 1.7.0
- kGuardian: 1.7.0
- Kanidm: (identity provider)

Check `.mise.toml` for exact versions of all tools.

## Recent Notable Changes

- **2026-03-19**: Added self-hosted Zitadel identity platform at login.00o.sh for SaaS development (network-isolated, external-only access, PostgreSQL backend, NetworkPolicy restricting traffic to Postgres egress and Envoy ingress only)
- **2026-03-07**: Added ambersecurityinc runner scale set to actions-runner-system (minRunners: 1, maxRunners: 3, 25Gi storage, 1Password integration)
- **2026-03-07**: Added ARC Grafana monitoring dashboard for runner autoscaling metrics
- **2026-03-07**: Added VolSync mass point-in-time restore script (`scripts/volsync-restore-all.sh`) for all 16 VolSync-backed apps
- **2026-03-07**: Added label generation script (`scripts/generate-labels.sh`) for auto-generating GitHub label config from directory structure
- **2026-03-07**: Added comprehensive MkDocs Material documentation site at docs.00o.sh (35 pages covering architecture, infrastructure, applications, operations, development)
- **2026-03-07**: Flux CD updated from 2.7.5 to 2.8.1
- **2026-03-07**: Tool updates: 1password-cli 2.30.0 → 2.32.1, helmfile 1.3.2 → 1.4.1, cue 0.15.4 → 0.16.0
- **2026-03-07**: kube-prometheus-stack updated to 82.10.1, Kromgo to v0.8.0, n8n to 2.11.1, Recyclarr to 8.4.0
- **2026-03-01**: Restored 1Password Connect Server for reads, added 1Password SDK ClusterSecretStore (`onepassword-sdk`) for write access via PushSecret
- **2026-03-01**: Migrated External Secrets from 1Password Connect Server to 1Password SDK (removed connect-api/connect-sync deployment, uses service account token directly)
- **2026-02-25**: Added UI Bakery low-code internal tool builder to ui-bakery namespace (7 microservices, MariaDB backend, ExternalSecrets, Envoy Gateway ingress at uibakery.00o.sh)
- **2026-02-22**: Added containerized FreePBX telephony platform to voip namespace (MariaDB backend, ExternalSecrets, Envoy Gateway ingress)
- **2026-02-22**: Added MariaDB Operator with MariaDB 11.7 Galera cluster (3 instances, 20Gi storage, S3 backups to Garage)
- **2026-02-22**: Documentation audit: fixed SOPS version (3.11.0 → 3.12.1), added docs.yaml and renovate-config.yaml workflows, fixed database app listing, updated architecture namespace map
- **2026-02-16**: Added error-pages service for Envoy Gateway with responseOverride redirects (403, 404, 500, 502, 503, 504)
- **2026-02-16**: Added n8n workflow automation platform to utils namespace (PostgreSQL backend, ExternalSecrets)
- **2026-02-14**: Added Kanidm identity provider with OAuth2 SSO for dbgate, forgejo, kubevirt-manager, opencost, penpot
- **2026-02-14**: Added Forgejo self-hosted Git service and Forgejo runner system
- **2026-02-14**: Added Homepage cluster dashboard to utils namespace
- **2026-02-14**: Added DBGate database management UI to database namespace
- **2026-02-14**: Added kGuardian security monitoring to kube-system
- **2026-02-14**: Added OpenCost Kubernetes cost analysis to observability
- **2026-02-14**: Added macvtap-cni and unifi-toolkit to network namespace
- **2026-02-14**: Added FreePBX telephony VMs (3 instances: b1-k3s01, b2-k3s01, b3-k3s01)
- **2026-02-14**: Added VM task automation (.taskfiles/vm/Taskfile.yaml)
- **2026-02-14**: Added label-generate workflow for automated label management
- **2026-02-14**: Talos Linux updated from 1.12.2 to 1.12.4
- **2026-02-14**: Helm updated from 4.1.0 to 4.1.1
- **2026-02-14**: PostgreSQL HA cluster expanded from 2 to 3 instances
- **2026-02-04**: Added KubeVirt virtualization namespace with VMs (debian-desktop, debian-server, ubuntu-server, windows-server)
- **2026-02-04**: Added Spegel for peer-to-peer container image sharing in kube-system
- **2026-02-04**: Added kubevirt-manager web UI for VM management
- **2026-02-04**: Added Grafana dashboards for Kubernetes infrastructure monitoring
- **2026-02-04**: Python updated from 3.14.2 to 3.14.3
- **2026-02-04**: VictoriaLogs datasource plugin updated to 0.24.0
- **2026-01-31**: Added database namespace with CloudNative-PG (PostgreSQL 17.7 HA cluster) and Dragonfly operator
- **2026-01-31**: Added Penpot design platform to utils namespace (backend, frontend, exporter, valkey)
- **2026-01-31**: Talos Linux updated from 1.12.1 to 1.12.2
- **2026-01-31**: Helm updated from 4.0.5 to 4.1.0
- **2026-01-31**: Penpot images updated to 2.12.1, Valkey upgraded to 9.0.1
- **2026-01-31**: kube-prometheus-stack updated to 81.4.2, Dragonfly operator to v1.4.0
- **2026-01-21**: Added GitHub Actions self-hosted runner system (actions-runner-system namespace)
- **2026-01-21**: Added SMTP relay service for outbound email (utils namespace with Maddy)
- **2026-01-21**: New CI/CD workflows for automated image pulling and CRD schema publishing
- **2026-01-15**: Expanded media stack with Radarr, Sonarr, Seerr, Recyclarr, Tautulli, FlareSolverr, TheLounge
- **2026-01-09**: Buddy heartbeat monitoring disabled in observability stack
- **2026-01-09**: Added comprehensive GitHub label automation (labeler and label-sync workflows)
- **2026-01-08**: Multiple media applications added (Plex, Bazarr, Autobrr, Prowlarr, qBittorrent)
- **2026-01-08**: Volsync backup schedule changed from every 5 minutes to daily at 2 AM
- **2026-01-08**: Discord webhook integration added to AlertManager
- **2026-01-08**: NFS-scaler component added using KEDA for smart scaling

## Component Deep Dives

### KubeVirt Virtualization Platform

Located in `kubernetes/apps/kubevirt/`, this namespace provides virtual machine capabilities within the Kubernetes cluster.

**Components**:
- **kubevirt**: KubeVirt operator for VM lifecycle management
- **cdi**: Containerized Data Importer for VM disk provisioning
- **kubevirt-manager**: Web UI for VM management (exposed at `kubevirt.00o.sh`)
- **virtualmachines**: Pre-configured VM templates and instances

**Features Enabled**:
- LiveMigration (move VMs between nodes without downtime)
- Macvtap (direct network attachment for VMs)
- HotplugVolumes (attach/detach volumes without restart)
- HostDevices and GPU passthrough support
- NetworkBindingPlugins for advanced networking

**Current VMs**:
- **debian-desktop**: Debian 13 with XFCE4 desktop environment (1 CPU, 1G RAM, 50Gi NFS storage)
- **debian-server**: Debian 13 headless server (1 CPU, 1G RAM, 50Gi NFS storage)
- **ubuntu-server**: Ubuntu server instance
- **windows-server**: Windows Server 2022 with virtio drivers (2 CPU, 2G RAM, 60Gi NFS storage)
- **freepbx-b1-k3s01**: FreePBX telephony/PBX system (with secrets)
- **freepbx-b2-k3s01**: FreePBX telephony/PBX system (with secrets)
- **freepbx-b3-k3s01**: FreePBX telephony/PBX system (with secrets)

**Storage**:
- Uses NFS (nfs-fast storageClass) for VM disks with ReadWriteMany access
- Enables live migration between nodes
- CDI uses openebs-hostpath for scratch space during imports

**Networking**:
- VMs use Multus with macvtap for direct network access
- Each VM has a dedicated MAC address
- DNS endpoints configured via external-dns

**CLI Tool**: Use `virtctl` from mise for VM management:
```bash
virtctl console <vm-name>      # Access VM console
virtctl ssh <vm-name>          # SSH into VM (if supported)
virtctl start/stop <vm-name>   # Start/stop VM
virtctl migrate <vm-name>      # Live migrate VM
```

### Spegel (Peer-to-Peer Image Sharing)

Located in `kubernetes/apps/kube-system/spegel/`, this component enables peer-to-peer container image sharing between cluster nodes.

**How it works**:
- Nodes share container images directly with each other
- Reduces external registry pulls and bandwidth usage
- Provides resilience when external registries are unavailable
- Uses containerd's registry mirroring capabilities

**Configuration**:
- Registry host port: 29999
- Mirror resolve timeout: 5s (increased from default 20ms for reliability)
- Mirror resolve retries: 3
- Containerd socket: /run/containerd/containerd.sock
- Registry config path: /etc/cri/conf.d/hosts

**Monitoring**:
- Grafana dashboard enabled (via GrafanaOperator)
- ServiceMonitor for Prometheus metrics

**Benefits**:
- Faster image pulls for frequently used images
- Reduced egress costs and external network dependency
- Automatic image distribution across nodes

### GitHub Actions Self-Hosted Runner System

Located in `kubernetes/apps/actions-runner-system/`, this system provides self-hosted GitHub Actions runners within the Kubernetes cluster.

**Components**:
- **actions-runner-controller**: Manages GitHub Actions Runner Scale Sets
- **runners**: Ephemeral runner pods that execute GitHub Actions workflows

**Runner Scale Sets**:
- **special-winner**: Runners for this repository's workflows
- **ambersecurityinc**: Runners for the ambersecurityinc GitHub organization (minRunners: 1, maxRunners: 3, 25Gi storage)

**How it works**:
- Uses GitHub's official Actions Runner Controller (ARC) architecture
- Creates on-demand runner pods for workflow jobs
- Scales based on GitHub webhook events
- Provides isolated execution environment with cluster access
- Used by workflows like `image-pull.yaml` and `schemas.yaml` that need cluster access
- Grafana dashboard for ARC monitoring (autoscaling runner set metrics)

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

### Database Infrastructure

Located in `kubernetes/apps/database/`, this namespace provides centralized database services for the cluster.

**CloudNative-PG (PostgreSQL)**:
- Kubernetes-native PostgreSQL operator
- Runs PostgreSQL 17.7 with 3 instances for high availability
- Uses OpenEBS hostpath storage (20Gi per instance)
- Pod anti-affinity for distribution across hosts
- Automated backups to Garage S3 storage via barman-cloud plugin
- Monitoring enabled via PodMonitor
- Tuned for performance: 200 max connections, 256MB shared_buffers, 512MB effective_cache_size
- Resources: 100m CPU request, 512Mi memory request, 2Gi memory limit

**Cluster Architecture**:
```
kubernetes/apps/database/cloudnative-pg/
├── app/                    # Operator deployment
│   ├── helmrelease.yaml
│   └── ocirepository.yaml
├── cluster/               # PostgreSQL cluster definition
│   ├── cluster.yaml       # Main cluster spec
│   ├── scheduledbackup.yaml
│   └── externalsecret.yaml
└── recovery/              # Disaster recovery configs
    └── cluster.yaml
```

**Dragonfly**:
- Modern Redis-compatible in-memory datastore
- Deploys the Dragonfly Operator for managing Dragonfly instances
- Higher performance alternative to Redis/Valkey
- Used by applications requiring fast caching or session storage

**MariaDB Operator (MariaDB Galera)**:
- Kubernetes-native MariaDB operator with Galera multi-master replication
- Runs MariaDB 11.7 with 3 instances for high availability
- Uses OpenEBS hostpath storage (20Gi per instance)
- Pod anti-affinity for distribution across hosts
- Automated scheduled backups to Garage S3 storage (every 6 hours, 30-day retention)
- Metrics and ServiceMonitor enabled
- Tuned for performance: 200 max connections, 256MB innodb_buffer_pool_size
- Resources: 100m CPU request, 512Mi memory request, 2Gi memory limit
- CRDs and operator installed via separate HelmReleases from `helm.mariadb.com`

**MariaDB Architecture**:
```
kubernetes/apps/database/mariadb-operator/
├── app/                       # Operator deployment
│   ├── helmrelease-crds.yaml  # CRDs HelmRelease
│   ├── helmrelease.yaml       # Operator HelmRelease
│   └── helmrepository.yaml    # Helm repo source
├── cluster/                   # MariaDB Galera cluster
│   ├── mariadb.yaml          # MariaDB CR (Galera)
│   ├── backup.yaml           # Scheduled S3 backup
│   └── externalsecret.yaml   # 1Password credentials
└── ks.yaml                   # Flux Kustomizations
```

**Usage**:
- Applications can connect to PostgreSQL via the `postgres-rw.database.svc.cluster.local` service.
- Applications can connect to MariaDB via the `mariadb.database.svc.cluster.local` service.
- Primary-only connections: `mariadb-primary.database.svc.cluster.local`
- Read replicas: `mariadb-secondary.database.svc.cluster.local`

### Penpot Design Platform

Located in `kubernetes/apps/utils/penpot/`, Penpot is an open-source design and prototyping platform.

**Components**:
- **Backend**: Main application server (penpotapp/backend:2.12.1)
- **Frontend**: Web UI (penpotapp/frontend:2.12.1)
- **Exporter**: Export service for file generation (penpotapp/exporter:2.12.1)
- **Valkey**: Redis-compatible cache (valkey/valkey:9.0.1-alpine)

**Architecture**:
- Multi-controller deployment using app-template Helm chart
- PostgreSQL database (via CloudNative-PG postgres-cluster)
- Valkey for session storage and caching
- Persistent storage for assets via Volsync (20Gi)
- Exposed at `penpot.00o.sh` via Envoy Gateway

**Dependencies**:
- Volsync (for persistent storage)
- postgres-cluster (for database)
- onepassword (for secrets)

**Configuration**:
- Registration and password login enabled
- Email verification disabled
- Telemetry disabled
- Automatic pod restarts via Reloader on secret changes

### Kanidm Identity Provider

Located in `kubernetes/apps/identity/kanidm/`, Kanidm provides centralized identity management and SSO for the cluster.

**How it works**:
- Modern identity provider with OAuth2/OIDC support
- Provides single sign-on for multiple cluster applications
- Manages user accounts, groups, and authentication policies

**OAuth2 Integrations**:
- **DBGate**: Database management UI authentication
- **Forgejo**: Git service authentication
- **KubeVirt Manager**: VM management UI authentication
- **OpenCost**: Cost analysis dashboard authentication
- **Penpot**: Design platform authentication

**Important**: When adding new applications that have a web UI, always consider whether Kanidm SSO integration should be configured. Each OAuth2 client is defined in a separate YAML file under `kubernetes/apps/identity/kanidm/app/`.

### Forgejo (Self-Hosted Git)

Located in `kubernetes/apps/utils/forgejo/`, Forgejo is a lightweight, self-hosted Git service.

**Features**:
- Git repository hosting
- Kanidm SSO integration for authentication
- Forgejo Actions (CI/CD) via forgejo-runner-system namespace

**Related**: The `forgejo-runner-system` namespace provides on-demand CI/CD runners using KEDA ScaledJobs that scale based on Forgejo webhook events.

### kGuardian (Security Monitoring)

Located in `kubernetes/apps/kube-system/kguardian/`, kGuardian provides security monitoring and guardianship for the Kubernetes cluster.

**Components**:
- **Broker** (v1.6.0): Message broker for security events
- **Controller** (v1.7.0): Core security monitoring engine
- **Frontend** (v1.6.2): Web UI for security insights
- **PostgreSQL**: Uses external CloudNative-PG database (init container for DB setup)

**Configuration**:
- LLM Bridge: disabled
- MCP Server: disabled
- Excluded namespaces: kube-system (from database monitoring)

### OpenCost (Cost Monitoring)

Located in `kubernetes/apps/observability/opencost/`, OpenCost provides Kubernetes cost monitoring and analysis.

**Features**:
- Real-time cost allocation and analysis
- Kanidm SSO integration for dashboard access
- Integrates with Prometheus for metrics

### Homepage (Cluster Dashboard)

Located in `kubernetes/apps/utils/homepage/`, Homepage provides a unified dashboard for all cluster services and applications.

**Purpose**: Central entry point for accessing all deployed services with status monitoring.

### VolSync Mass Restore

The `scripts/volsync-restore-all.sh` script provides automated point-in-time restore for all 16 VolSync-backed applications.

**Supported Apps**:
- **Media (12)**: autobrr, bazarr, plex, prowlarr, qbittorrent, radarr, recyclarr, seerr, sonarr, tautulli, thelounge, qui
- **Network (1)**: unifi-toolkit
- **Observability (1)**: gatus
- **Utils (2)**: forgejo, penpot

**Workflow**:
1. Suspends Flux Kustomizations
2. Scales down app workloads (handles both Deployments and StatefulSets)
3. Patches ReplicationDestinations with `restoreAsOf` timestamp and manual trigger
4. Waits for restores to complete (20-minute timeout per app)
5. Resumes Kustomizations on success

**Usage**: Edit the `RESTORE_TIME` variable in the script (default: `2026-03-01T23:59:59Z`) and run:
```bash
./scripts/volsync-restore-all.sh
```

### Documentation Site

The repository includes a comprehensive MkDocs Material documentation site published at [docs.00o.sh](https://docs.00o.sh).

**Structure** (35 pages):
- **Getting Started**: Prerequisites, configuration, bootstrap, post-install
- **Infrastructure**: Talos, Flux, Cilium, Envoy, storage, databases, certs/DNS, secrets, identity/SSO
- **Applications**: Media stack, FreePBX, virtualization, observability, utilities
- **Operations**: Day-2 ops, backup/recovery, VM management, troubleshooting
- **Development**: Templates, CI/CD pipelines, contributing
- **Research**: SSO providers

**Configuration**: `mkdocs.yml` at repository root
**Build**: `mkdocs build` or pushed automatically via `docs.yaml` workflow
**Deploy**: Cloudflare Pages (`special-winner-docs` project)

---

**Last Updated**: 2026-03-07
**Template Source**: [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)
