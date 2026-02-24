# 1Password SDK Migration & Secrets Architecture

Research document for migrating from 1Password Connect to 1Password SDK provider, and restructuring cluster-secrets for multi-cluster support.

**Date**: 2026-02-24
**Status**: Proposed
**Scope**: External Secrets Operator provider migration + cluster-secrets architecture

---

## Executive Summary

The current 1Password Connect provider is **deprecated** by External Secrets Operator. ESO recommends migrating to the 1Password SDK provider, which eliminates the Connect server deployment entirely. Combined with replacing the SOPS-based `cluster-secrets` with a `ClusterExternalSecret`, this migration solves the multi-cluster secrets problem and simplifies operations.

---

## Current Architecture

### 1Password Connect (what we have today)

```
1Password Cloud
       |
       v
1Password Connect Server (3 replicas)
  ├── API container (ghcr.io/1password/connect-api:1.8.1)
  └── Sync container (ghcr.io/1password/connect-sync:1.8.1)
       |
       v
ClusterSecretStore "onepassword"
  (connectHost: http://onepassword.external-secrets.svc.cluster.local)
       |
       v
43 ExternalSecret resources across 14 namespaces
       |
       v
Kubernetes Secrets (consumed by applications)
```

**Files involved:**
- `kubernetes/apps/external-secrets/onepassword/app/helmrelease.yaml` -- Connect server deployment (3 replicas, 6 containers total)
- `kubernetes/apps/external-secrets/onepassword/app/clustersecretstore.yaml` -- Provider config
- `kubernetes/apps/external-secrets/onepassword/app/secret.sops.yaml` -- SOPS-encrypted credentials.json + token
- `bootstrap/onepassword-secret.sops.yaml` -- Bootstrap copy of credentials

**Authentication:** Requires two secrets:
1. `1password-credentials.json` -- Connect server credentials file
2. `token` -- API access token

### cluster-secrets (the multi-cluster problem)

```
kubernetes/components/sops/
├── cluster-secrets.sops.yaml    # SOPS-encrypted Secret (only has SECRET_DOMAIN!)
└── kustomization.yaml           # Kustomize Component

Included by 10 namespace kustomization.yaml files:
  cert-manager, database, default, external-secrets, flux-system,
  identity, kube-system, kubevirt, media, network
```

**Problem:** The template (`cluster-secrets.sops.yaml.j2`) defines 15 variables, but the committed SOPS file only contains `SECRET_DOMAIN`. The other 14 variables are missing:

| Variable | Status | Used by |
|----------|--------|---------|
| `CLUSTER_NAME` | **MISSING** | Identification |
| `SECRET_DOMAIN` | Present | 30+ resources (certs, routes, DNS) |
| `CLUSTER_POD_CIDR` | **MISSING** | Cilium native routing |
| `CLUSTER_SVC_CIDR` | **MISSING** | Service CIDR |
| `CLUSTER_DNS_ADDR` | **MISSING** | CoreDNS clusterIP |
| `CLUSTER_API_ADDR` | **MISSING** | Kubernetes API VIP |
| `CLUSTER_GATEWAY_ADDR` | **MISSING** | Envoy Gateway internal LB |
| `CLUSTER_DNS_GATEWAY_ADDR` | **MISSING** | k8s-gateway LB |
| `CLOUDFLARE_GATEWAY_ADDR` | **MISSING** | Envoy Gateway external LB |
| `CLOUDFLARE_TOKEN` | **MISSING** | Cloudflare API |
| `CLOUDFLARE_TUNNEL_ID` | **MISSING** | Tunnel CNAME target |
| `NODE_CIDR` | **MISSING** | Node network |
| `CILIUM_LB_MODE` | **MISSING** | Cilium LB config |
| `SUSPEND_DEFAULT` | **MISSING** | Failover suspension |

**Why this is a multi-cluster blocker:** A single SOPS file produces the same Secret for all clusters. Both 3226 and usny01 would get identical IPs/CIDRs, which is wrong.

---

## 1Password SDK vs Connect: Comparison

### Feature Comparison

| Feature | Connect (current) | SDK (recommended) |
|---------|-------------------|-------------------|
| **ESO Status** | Deprecated | Active, recommended |
| **Infrastructure** | 3-replica deployment (6 containers) | None (direct API calls) |
| **Authentication** | credentials.json + token | Service account token only |
| **Token lifetime** | No documented limit | 90 days (requires rotation) |
| **Caching** | Server-side (Connect acts as proxy) | Client-side (ESO 2.0.0+, configurable TTL) |
| **Downtime resilience** | High (Connect caches locally) | Medium (client cache, configurable) |
| **Resource usage** | ~10m CPU, 64Mi RAM x 6 containers | Zero (uses ESO operator only) |
| **Secret transport** | Unencrypted within cluster (Connect -> ESO) | Direct encrypted API to 1Password |
| **Setup complexity** | High (Connect server + credentials file) | Low (single token) |
| **Vault reference** | Numeric ID (`1`) | Vault name (`"Kubernetes"`) |

### Security Comparison

| Aspect | Connect | SDK |
|--------|---------|-----|
| Attack surface | Connect server pods, internal network | ESO operator only |
| Credential type | Long-lived credentials.json | Time-limited service account token |
| Network exposure | Internal service endpoint | Direct outbound HTTPS only |
| Secret in transit | Unencrypted between Connect and ESO | Encrypted end-to-end |

### Operational Comparison

| Aspect | Connect | SDK |
|--------|---------|-----|
| Maintenance | Image updates, pod monitoring, probe tuning | Token renewal every 90 days |
| Debugging | Connect logs + ESO logs | ESO logs only |
| Failure recovery | Pod restart, replica failover | Automatic retry by ESO |
| Resource overhead | ~60m CPU, ~384Mi RAM total | 0 additional |
| SOPS dependency | Yes (encrypted credentials.json) | Yes (encrypted token) or manual |

---

## Recommendation: Migrate to 1Password SDK

### Rationale

1. **Connect is deprecated** -- no new features, will eventually be removed from ESO
2. **Eliminates 6 containers** -- removes the Connect server deployment entirely
3. **Simpler authentication** -- single service account token instead of credentials.json + token
4. **Better security** -- no unencrypted secret transport within the cluster
5. **ESO 2.0.0 alignment** -- SDK caching added in 2.0.0, which we're already running
6. **Multi-cluster ready** -- each cluster can use its own service account token

### Token Rotation Strategy

The 90-day token limit requires a rotation process. Options:

1. **1Password automation** -- Use `op` CLI in a CronJob to refresh the token
2. **External workflow** -- GitHub Action or n8n workflow to rotate and update the Secret
3. **Manual** -- Calendar reminder, rotate via `op service-account rotate-token`

**Recommendation:** Use n8n (already deployed) with a scheduled workflow that rotates the token and updates the Kubernetes Secret.

---

## Proposed Architecture

### 1Password SDK Setup

```yaml
# kubernetes/apps/external-secrets/onepassword/app/clustersecretstore.yaml
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepassword:
      auth:
        serviceAccountSecretRef:
          name: onepassword-sdk-secret
          namespace: external-secrets
          key: token
  # SDK caching (ESO 2.0.0+)
  conditions:
    - type: Ready
      status: "True"
```

```yaml
# kubernetes/apps/external-secrets/onepassword/app/secret.sops.yaml
# (replaces credentials.json + token with just the SA token)
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-sdk-secret
type: Opaque
stringData:
  token: <SOPS-encrypted service account token>
```

### cluster-secrets via ClusterExternalSecret

Replace the SOPS component with a `ClusterExternalSecret` that creates `cluster-secrets` in every namespace:

```yaml
# kubernetes/apps/external-secrets/cluster-secrets/app/clusterexternalsecret.yaml
---
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: cluster-secrets
spec:
  # Target namespaces that need cluster-secrets
  namespaceSelectors:
    - matchLabels:
        cluster-secrets: "true"
  refreshTime: 1h
  externalSecretSpec:
    refreshInterval: 1h
    secretStoreRef:
      kind: ClusterSecretStore
      name: onepassword
    target:
      name: cluster-secrets
      creationPolicy: Owner
    dataFrom:
      - extract:
          key: cluster-secrets
```

```yaml
# kubernetes/apps/external-secrets/cluster-secrets/ks.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-secrets
  labels:
    cluster.home/role: infra
spec:
  dependsOn:
    - name: onepassword
  interval: 1h
  path: ./kubernetes/apps/external-secrets/cluster-secrets/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: external-secrets
  wait: true
```

### Namespace Labels

Add `cluster-secrets: "true"` label to every namespace that needs cluster-secrets:

```yaml
# Example: kubernetes/apps/cert-manager/namespace.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
  labels:
    cluster-secrets: "true"
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

### Per-Cluster 1Password Items

Each cluster gets its own 1Password item. The `ClusterExternalSecret` uses a fixed item name (`cluster-secrets`), and each cluster's 1Password vault contains its own values.

**Alternative:** If sharing one vault, use per-cluster item names (`cluster-3226`, `cluster-usny01`) and inject the cluster name via Flux substitution. This requires `CLUSTER_NAME` in the root ks.yaml's `postBuild.substitute`.

| Approach | Pros | Cons |
|----------|------|------|
| **Separate vaults per cluster** | Clean isolation, same item name | More 1Password setup, separate tokens |
| **Same vault, different item names** | Simple, one token | Requires Flux substitution for item name |
| **Same vault, same item name** | Simplest | Only works if clusters don't share a vault |

**Recommendation:** Same vault, different item names (`cluster-3226`, `cluster-usny01`). Use Flux substitution to inject the cluster name:

```yaml
# In ClusterExternalSecret (gets CLUSTER_NAME from Flux substitution)
dataFrom:
  - extract:
      key: cluster-${CLUSTER_NAME}
```

This requires the `cluster-secrets` Kustomization to NOT use `substituteFrom: cluster-secrets` (circular), but instead receive `CLUSTER_NAME` from a ConfigMap or the root ks.yaml's substitute.

---

## Other SOPS Secrets to Migrate

Five SOPS-encrypted secrets remain in `kubernetes/apps/`:

| File | Secret Name | Key(s) | Migrate? |
|------|-------------|--------|----------|
| `cert-manager/cert-manager/app/secret.sops.yaml` | cert-manager-secret | `api-token` (Cloudflare) | Yes -- already in 1Password |
| `network/cloudflare-dns/app/secret.sops.yaml` | cloudflare-dns-secret | `api-token` (Cloudflare) | Yes -- same Cloudflare token |
| `network/cloudflare-tunnel/app/secret.sops.yaml` | cloudflare-tunnel-secret | `TUNNEL_TOKEN` | Yes -- per-cluster tunnel token |
| `flux-system/flux-instance/app/secret.sops.yaml` | github-webhook-token-secret | `token` | Low priority -- shared |
| `external-secrets/onepassword/app/secret.sops.yaml` | onepassword credentials | `credentials.json`, `token` | Replaced by SDK token |

**Phase 1 (with this migration):** Migrate cert-manager, cloudflare-dns, cloudflare-tunnel (these use cluster-specific values)
**Phase 2 (later):** Migrate flux-instance webhook token (low priority, shared across clusters)

---

## Bootstrap Considerations

### Bootstrap SOPS secrets (keep as-is)

These SOPS-encrypted secrets are used during initial cluster bootstrap, before ESO is running:

| File | Purpose | Keep SOPS? |
|------|---------|------------|
| `bootstrap/sops-age.sops.yaml` | Age key for Flux SOPS decryption | Yes -- required for Flux bootstrap |
| `bootstrap/onepassword-secret.sops.yaml` | 1Password credentials | Yes -- changes to SDK token only |
| `bootstrap/github-deploy-key.sops.yaml` | Git SSH key (private repos) | Yes -- needed before Flux |

**Bootstrap flow with SDK:**
1. Apply `sops-age.sops.yaml` (Flux can decrypt SOPS)
2. Apply `onepassword-sdk-secret` (SDK token, SOPS-encrypted)
3. Apply `github-deploy-key.sops.yaml` (if private repo)
4. Start Flux operator + instance
5. Flux deploys ESO + ClusterSecretStore (SDK)
6. ESO creates `cluster-secrets` from 1Password
7. All apps can now resolve `${VARIABLE}` substitutions

### Chicken-and-egg: cluster-secrets availability

Apps that depend on `cluster-secrets` variables will fail to substitute on their first reconciliation if `cluster-secrets` doesn't exist yet. Flux behavior:

- **Missing Secret:** Flux logs a warning, applies resources with unsubstituted `${VAR}` strings
- **Effect:** Resources with literal `${VAR}` in annotations/values will be misconfigured
- **Recovery:** Once ESO creates cluster-secrets, next Flux reconciliation fixes everything

**Mitigation:** The `cluster-secrets` Kustomization has `wait: true` and `dependsOn: onepassword`. Apps that depend on `cluster-secrets` should add `dependsOn: cluster-secrets` in their ks.yaml. However, this creates a long dependency chain.

**Practical approach:** Accept that first reconciliation may have missing substitutions. Flux's 1h interval will self-heal once ESO creates cluster-secrets. For faster recovery, run `task reconcile` after bootstrap.

---

## Migration Checklist

### Pre-migration

- [ ] Create 1Password service account: `op service-account create eso-kubernetes --vault Kubernetes`
- [ ] Store the service account token securely
- [ ] Create 1Password items: `cluster-3226` and `cluster-usny01` with all 15 variables
- [ ] Test SDK token can access the vault: `op read "op://Kubernetes/cluster-3226/CLUSTER_NAME" --account <account>`

### Code changes

- [ ] Update `clustersecretstore.yaml` to SDK provider (remove connectHost, add serviceAccountSecretRef)
- [ ] Replace `onepassword/app/secret.sops.yaml` with SDK token only
- [ ] Create `cluster-secrets/` directory with ClusterExternalSecret
- [ ] Add `cluster-secrets: "true"` label to 10 namespaces
- [ ] Remove `../../components/sops` from 10 namespace kustomization.yaml files
- [ ] Delete `kubernetes/components/sops/` directory
- [ ] Add `cluster-secrets` ks.yaml to external-secrets kustomization
- [ ] Update `onepassword/app/helmrelease.yaml` -- remove Connect server deployment
- [ ] Update `bootstrap/onepassword-secret.sops.yaml` with SDK token format
- [ ] Create ExternalSecrets for cert-manager, cloudflare-dns, cloudflare-tunnel secrets

### Validation

- [ ] `kustomize build kubernetes/apps/` succeeds without sops component
- [ ] flux-local validates all Kustomizations
- [ ] ClusterExternalSecret schema validates with kubeconform
- [ ] Test ExternalSecret in a staging namespace before full rollout

### Post-migration

- [ ] Verify all 10 namespaces have `cluster-secrets` Secret
- [ ] Verify all 15 keys are present in each Secret
- [ ] Verify Flux reconciliation completes without substitution errors
- [ ] Set up token rotation schedule (every 60 days to leave buffer)
- [ ] Remove old Connect-related resources from 1Password
- [ ] Update CLAUDE.md documentation

---

## References

- [ESO 1Password SDK Provider](https://external-secrets.io/latest/provider/1password-sdk/)
- [ESO 1Password Connect Provider (deprecated)](https://external-secrets.io/latest/provider/1password-automation/)
- [ESO ClusterExternalSecret API](https://external-secrets.io/latest/api/clusterexternalsecret/)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [Flux CD Variable Substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
