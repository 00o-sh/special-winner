# Day-2 Operations

## Flux Reconciliation

Force Flux to pull the latest changes from Git:

```sh
task reconcile
```

Check the status of all Flux resources:

```sh
flux get ks -A       # Kustomizations
flux get hr -A       # HelmReleases
flux get sources -A  # All sources
```

## Talos Operations

### Update Node Configuration

```sh
# Regenerate configs from templates
task talos:generate-config

# Apply to a specific node
task talos:apply-node IP=10.10.10.10 MODE=auto
```

### Upgrade Talos

1. Update `talosVersion` in `talenv.yaml`
2. Run:

```sh
task talos:upgrade-node IP=10.10.10.10
```

### Upgrade Kubernetes

1. Update `kubernetesVersion` in `talenv.yaml`
2. Run:

```sh
task talos:upgrade-k8s
```

## Application Management

### Suspend an Application

```sh
flux suspend hr <app-name> -n <namespace>
```

### Resume an Application

```sh
flux resume hr <app-name> -n <namespace>
```

### Force Redeploy

```sh
flux reconcile hr <app-name> -n <namespace> --force
```

### Roll Back a HelmRelease

```sh
# Check history
helm history <release-name> -n <namespace>

# Rollback
helm rollback <release-name> <revision> -n <namespace>
```

## Cluster Failover

The repository supports active/standby cluster failover. One cluster runs all workloads while the other keeps only infra running (Flux, Cilium, CoreDNS, cert-manager, OpenEBS, External Secrets).

### How It Works

- The `active-cluster` file at repo root defines which cluster is active (e.g. `3226`)
- Each cluster's root `ks.yaml` (`kubernetes/flux/<cluster>/ks.yaml`) has `SUSPEND_DEFAULT` in `postBuild.substitute`
- A Flux patch injects `suspend: ${SUSPEND_DEFAULT}` into all non-infra Kustomizations
- Infra apps have `cluster.home/role: infra` label and are excluded from the patch
- Cloudflare tunnel credentials are shared between clusters (same tunnel ID, seamless DNS)

### Failover Methods

**Local task** (recommended):

```sh
task failover CLUSTER=usny01
```

This updates the `active-cluster` file and both root `ks.yaml` files locally. Then commit and push.

**Git-only (CI handles it)**:

Edit the `active-cluster` file, commit, and push. The `failover.yaml` GitHub Action automatically updates both root `ks.yaml` files and commits the changes.

### What Stays Running on Standby

These infra namespaces are never suspended:

- `cert-manager`
- `flux-system`
- `kube-system` (Cilium, CoreDNS, etc.)
- `openebs-system`
- `external-secrets`

### Adding a New Infra App

To mark an app as infra (never suspended during failover), add the `cluster.home/role: infra` label to its `ks.yaml`:

```yaml
metadata:
  labels:
    cluster.home/role: infra
```

## Renovate

Renovate runs on a weekend schedule and creates PRs for dependency updates:

- **Auto-merge**: GitHub Actions (minor/patch), Mise tools (minor/patch)
- **Manual review**: Helm charts, container images (major versions)
- **Dashboard**: Check the "Dependency Dashboard" issue in GitHub

## Adding a New Application

Follow the checklist in order:

1. Create directory: `kubernetes/apps/<namespace>/<app-name>/app/`
2. Create manifests: `helmrelease.yaml`, `ocirepository.yaml`, `kustomization.yaml`
3. Create `ks.yaml` Flux Kustomization
4. Update `kubernetes/apps/<namespace>/kustomization.yaml`
5. Encrypt any secrets with SOPS
6. Consider Kanidm SSO integration
7. Add to Homepage dashboard
8. Add VolSync backup config if stateful
9. Add monitoring (ServiceMonitor/PodMonitor) if metrics are exposed
10. Add Discord alerts if critical
11. Add NFS-scaler if mounting NFS volumes
12. Update CLAUDE.md with the new application
