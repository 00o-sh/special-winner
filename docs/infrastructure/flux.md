# Flux CD

[Flux CD](https://fluxcd.io/) v2.7.5 provides GitOps continuous delivery, automatically syncing the cluster state from Git.

## Architecture

The cluster uses the **Flux Operator** pattern:

- **flux-operator** (v0.41.1) -- Manages Flux components lifecycle
- **flux-instance** (v0.41.1) -- Configured Flux deployment with performance tuning

### Performance Tuning

The Flux instance is configured with:

- **10 concurrent workers** for Kustomize and Helm controllers
- **1Gi memory limits** for controllers
- **Helm caching** enabled for faster reconciliation
- **OOM detection** enabled
- **SOPS decryption** configured for Age keys

## How It Works

```mermaid
graph TD
    A[Git Push] --> B[Flux detects change]
    B --> C[Reconcile Kustomizations]
    C --> D[Process HelmReleases]
    D --> E[Apply to Cluster]
    E --> F[Report Status]
```

1. Flux watches the Git repository (via webhook or polling)
2. Kustomizations define which paths to reconcile
3. HelmReleases deploy applications from OCI registries
4. SOPS secrets are decrypted automatically
5. Post-build variable substitution injects cluster secrets

## Key Patterns

### Kustomization

```yaml
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

### HelmRelease

```yaml
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
    # Application-specific values
```

## Common Operations

### Force Reconciliation

```sh
task reconcile
# or
flux --namespace flux-system reconcile kustomization flux-system --with-source
```

### Check Status

```sh
flux check                    # Health check
flux get sources git -A       # Git sources
flux get ks -A                # Kustomizations
flux get hr -A                # HelmReleases
```

### View Logs

```sh
flux logs --all-namespaces
```

### Suspend/Resume

```sh
flux suspend hr <name> -n <namespace>
flux resume hr <name> -n <namespace>
```
