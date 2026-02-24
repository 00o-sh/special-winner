# Multi-Cluster Branch Merge Strategy

Comprehensive plan for merging the `claude/multi-cluster-support-*` branch into `main` without breaking the production cluster (3226).

**Date**: 2026-02-24
**Status**: Proposed
**Branch**: `claude/multi-cluster-support-RVcdW` (8 commits ahead of main)

---

## What This Branch Changes

### Commits (oldest to newest)

1. **feat(kubernetes): prep multi-cluster support, name current cluster 3226** -- Per-cluster directory structure, CLUSTER parameter for tasks
2. **feat(kubernetes): prep cluster usny01 (US-NY-01, subnet 10.1.6.0/24)** -- New cluster directory and Flux entry point
3. **feat(kubernetes): add multi-cluster failover with SUSPEND_DEFAULT** -- Active/standby failover mechanism, infra labels
4. **docs: update documentation for multi-cluster support and failover** -- CLAUDE.md and docs updates
5. **docs(kubernetes): add usny01 Talos schematic ID and extensions** -- Talos extensions for usny01 hardware
6. **fix: resolve merge conflict in architecture diagram** -- Conflict resolution
7. **fix(kubernetes): fix multi-cluster variable scoping** -- SOPS_AGE_KEY_FILE and KUBECONFIG per-cluster
8. **fix(kubernetes): accept lowercase cluster variable in Taskfile** -- Case-insensitive CLUSTER parameter

### Key file changes (55 files, +953/-119 lines)

| Category | Changes |
|----------|---------|
| **Flux entry points** | `kubernetes/flux/cluster/ks.yaml` renamed to `kubernetes/flux/usny01/ks.yaml`; new `kubernetes/flux/3226/ks.yaml` |
| **flux-instance** | `path: kubernetes/flux/cluster` changed to `path: kubernetes/flux/3226` |
| **Infra labels** | Added `cluster.home/role: infra` to 17 Kustomizations (cert-manager, cilium, coredns, external-secrets, flux, openebs, etc.) |
| **Failover patch** | Root ks.yaml patches add `suspend: ${SUSPEND_DEFAULT}` to non-infra Kustomizations |
| **SUSPEND_DEFAULT** | 3226: `"false"` (active), usny01: `"true"` (standby) |
| **Task system** | All tasks accept `CLUSTER=<name>`, default `3226`; per-cluster KUBECONFIG/SOPS paths |
| **CI/CD** | New `failover.yaml` workflow; e2e tests updated for multi-cluster |
| **Cluster configs** | `clusters/3226/` and `clusters/usny01/` directories (config files gitignored) |
| **Template** | `.sops.yaml.j2` updated for multi-cluster path regex; cluster-secrets template adds 14 new variables |

---

## Critical Issues That MUST Be Fixed Before Merge

### Issue 1: Flux Path Rename Deadlock (BLOCKER)

**Severity:** Critical -- will permanently deadlock the production cluster

**The problem:**
```
CURRENT MAIN:
  flux-instance.helmrelease.yaml → path: kubernetes/flux/cluster
  kubernetes/flux/cluster/ks.yaml → exists (root Kustomization)

THIS BRANCH:
  flux-instance.helmrelease.yaml → path: kubernetes/flux/3226 (CHANGED)
  kubernetes/flux/cluster/ → RENAMED to kubernetes/flux/usny01/
  kubernetes/flux/3226/ks.yaml → NEW file
```

**What happens on merge:**
1. Merge lands on `main`
2. Flux on 3226 detects new commit, fetches latest `main`
3. Flux tries to reconcile using its current path: `kubernetes/flux/cluster`
4. **That directory no longer exists** (renamed to `usny01`)
5. Kustomize build fails -- root Kustomization cannot be built
6. No child Kustomizations reconcile, including `flux-instance`
7. `flux-instance` HelmRelease never updates to new path `kubernetes/flux/3226`
8. **Permanent deadlock** -- Flux cannot self-heal because it can't reach the file that tells it the new path

**Fix:** Keep `kubernetes/flux/cluster/ks.yaml` during the transition. Two options:

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| **A: Keep copy** | Copy `kubernetes/flux/3226/ks.yaml` to `kubernetes/flux/cluster/ks.yaml` | Simple, zero risk | Temporary duplicate file |
| **B: Pre-apply** | Manually update FluxInstance on cluster before merge | No duplicate | Requires cluster access, timing-sensitive |

**Recommendation:** Option A (keep copy). After merge, Flux reconciles via old path, picks up flux-instance change to new path, switches automatically. Then remove old path in follow-up PR.

### Issue 2: cluster-secrets Missing 14 Variables (HIGH)

**Severity:** High -- apps using `${CLUSTER_GATEWAY_ADDR}` etc. get empty strings

**Current state of committed `cluster-secrets.sops.yaml`:**
```yaml
stringData:
  SECRET_DOMAIN: ENC[AES256_GCM,data:pgmS8grW,...]
  # THAT'S IT. Only 1 of 15 variables.
```

**Template defines 15 variables**, of which these are actively used in manifests:

| Variable | Where used | Effect if empty/missing |
|----------|-----------|------------------------|
| `CLUSTER_POD_CIDR` | `cilium/helmrelease.yaml:39` ipv4NativeRoutingCIDR | Pod routing breaks |
| `CLUSTER_DNS_ADDR` | `coredns/helmrelease.yaml:20` clusterIP | CoreDNS service can't bind |
| `CLUSTER_GATEWAY_ADDR` | `envoy-gateway/envoy.yaml:85` LB IP | Internal ingress down |
| `CLUSTER_DNS_GATEWAY_ADDR` | `k8s-gateway/helmrelease.yaml:19` LB IP | Internal DNS resolution fails |
| `CLOUDFLARE_GATEWAY_ADDR` | `envoy-gateway/envoy.yaml:55` LB IP | External ingress down |
| `CLOUDFLARE_TUNNEL_ID` | `cloudflare-tunnel/dnsendpoint.yaml:10` CNAME | Tunnel routing breaks |
| `SECRET_DOMAIN` | 30+ resources | Present (OK) |
| `NODE_CIDR` | Not directly used in manifests yet | No immediate impact |
| `CILIUM_LB_MODE` | Not directly used in manifests yet | No immediate impact |
| `SUSPEND_DEFAULT` | Root ks.yaml patch only (inline substitute) | No impact (handled separately) |

**Why the cluster might still be working:** These variables were likely populated in the actual Kubernetes Secret during bootstrap (via `task configure` + SOPS encryption), and the git-committed SOPS file is stale. The git file was last encrypted 2025-11-25 (3 months ago) and may predate the template changes that added these variables.

**Fix:** Migrate cluster-secrets to ExternalSecret from 1Password (see [1Password SDK Migration](1password-sdk-migration.md)), OR re-render templates with `task configure CLUSTER=3226` to update the SOPS file.

### Issue 3: Single cluster-secrets for Multiple Clusters (HIGH)

**Severity:** High -- fundamentally incompatible with multi-cluster

**The problem:** `kubernetes/components/sops/cluster-secrets.sops.yaml` is a single file included by 10 namespace kustomization.yaml files. Both clusters' Flux instances point to the same `kubernetes/apps/` directory. They'd both create identical Secrets from the same SOPS file.

But 3226 needs `CLUSTER_GATEWAY_ADDR: 10.0.6.12` and usny01 needs `CLUSTER_GATEWAY_ADDR: 10.1.6.12`.

**Fix:** See [1Password SDK Migration](1password-sdk-migration.md) for the ExternalSecret approach. Per-cluster 1Password items provide cluster-specific values.

---

## Merge Plan: Three Phases

### Phase 0: Pre-merge preparation (manual, cluster access required)

**Goal:** Set up 1Password items and validate before touching any code.

| Step | Action | Validation |
|------|--------|------------|
| 0.1 | Create 1Password service account for ESO | `op service-account list` shows the account |
| 0.2 | Create 1Password item `cluster-3226` with all 15 variables | `op read "op://Kubernetes/cluster-3226/CLUSTER_NAME"` returns `3226` |
| 0.3 | Create 1Password item `cluster-usny01` with usny01-specific values | `op read "op://Kubernetes/cluster-usny01/NODE_CIDR"` returns `10.1.6.0/24` |
| 0.4 | Create 1Password items for other SOPS secrets (cert-manager, cloudflare) | `op read "op://Kubernetes/cloudflare/api-token"` works |
| 0.5 | Test SDK token connectivity from within the cluster | `kubectl run --rm -it test --image=1password/op:latest -- op read ...` |

**1Password item `cluster-3226` contents:**
```
CLUSTER_NAME        = 3226
SECRET_DOMAIN       = <domain>
CLUSTER_POD_CIDR    = 172.30.0.0/16
CLUSTER_SVC_CIDR    = 172.31.0.0/16
CLUSTER_DNS_ADDR    = 172.31.0.10
CLUSTER_API_ADDR    = <API VIP for 3226>
CLUSTER_GATEWAY_ADDR = 10.0.6.12
CLUSTER_DNS_GATEWAY_ADDR = 10.0.6.11
CLOUDFLARE_GATEWAY_ADDR  = 10.0.6.13
CLOUDFLARE_TOKEN    = <Cloudflare API token>
CLOUDFLARE_TUNNEL_ID = <tunnel UUID>
NODE_CIDR           = 10.0.6.0/24
CILIUM_LB_MODE      = dsr
SUSPEND_DEFAULT      = false
```

**1Password item `cluster-usny01` contents:**
```
CLUSTER_NAME        = usny01
SECRET_DOMAIN       = <domain>
CLUSTER_POD_CIDR    = 172.30.0.0/16
CLUSTER_SVC_CIDR    = 172.31.0.0/16
CLUSTER_DNS_ADDR    = 172.31.0.10
CLUSTER_API_ADDR    = <API VIP for usny01>
CLUSTER_GATEWAY_ADDR = 10.1.6.12
CLUSTER_DNS_GATEWAY_ADDR = 10.1.6.11
CLOUDFLARE_GATEWAY_ADDR  = 10.1.6.13
CLOUDFLARE_TOKEN    = <Cloudflare API token>
CLOUDFLARE_TUNNEL_ID = <same tunnel UUID for failover>
NODE_CIDR           = 10.1.6.0/24
CILIUM_LB_MODE      = dsr
SUSPEND_DEFAULT      = true
```

### Phase 1: Code changes on the branch (before merge)

**Goal:** Fix all blocking issues, migrate secrets architecture.

#### Step 1.1: Fix Flux path deadlock

Create `kubernetes/flux/cluster/ks.yaml` as a copy of `kubernetes/flux/3226/ks.yaml`:

```bash
cp kubernetes/flux/3226/ks.yaml kubernetes/flux/cluster/ks.yaml
# Add comment at top: # DEPRECATED: Remove after Flux switches to kubernetes/flux/3226
```

This ensures current Flux (looking at `kubernetes/flux/cluster`) can still reconcile.

**Transition flow after merge:**
1. Flux reconciles via old path `kubernetes/flux/cluster/ks.yaml`
2. flux-instance HelmRelease updates with `path: kubernetes/flux/3226`
3. Flux Operator updates FluxInstance CR
4. Flux switches to new path `kubernetes/flux/3226/ks.yaml`
5. Old path is no longer used (remove in Phase 3)

#### Step 1.2: Add CLUSTER_NAME to root ks.yaml files

Add `CLUSTER_NAME` to each cluster's `postBuild.substitute`:

```yaml
# kubernetes/flux/3226/ks.yaml
postBuild:
  substitute:
    SUSPEND_DEFAULT: "false"
    CLUSTER_NAME: "3226"

# kubernetes/flux/usny01/ks.yaml
postBuild:
  substitute:
    SUSPEND_DEFAULT: "true"
    CLUSTER_NAME: "usny01"

# kubernetes/flux/cluster/ks.yaml (deprecated copy)
postBuild:
  substitute:
    SUSPEND_DEFAULT: "false"
    CLUSTER_NAME: "3226"
```

**Why:** `CLUSTER_NAME` is needed by the ClusterExternalSecret to read the correct 1Password item per cluster.

#### Step 1.3: Migrate 1Password from Connect to SDK

Update these files:

| File | Change |
|------|--------|
| `external-secrets/onepassword/app/clustersecretstore.yaml` | Replace Connect provider with SDK provider |
| `external-secrets/onepassword/app/secret.sops.yaml` | Replace credentials.json+token with SDK service account token |
| `external-secrets/onepassword/app/helmrelease.yaml` | **Delete** -- Connect server no longer needed |
| `external-secrets/onepassword/app/ocirepository.yaml` | **Delete** -- no Helm chart needed |
| `external-secrets/onepassword/app/kustomization.yaml` | Update to remove helmrelease/ocirepository references |
| `external-secrets/onepassword/ks.yaml` | Remove healthCheck for HelmRelease (keep ClusterSecretStore check) |
| `bootstrap/onepassword-secret.sops.yaml` | Update to SDK token format |

#### Step 1.4: Create cluster-secrets ExternalSecret

Create new directory `kubernetes/apps/external-secrets/cluster-secrets/`:

```
kubernetes/apps/external-secrets/cluster-secrets/
├── app/
│   ├── clusterexternalsecret.yaml   # ClusterExternalSecret
│   └── kustomization.yaml
└── ks.yaml                          # Flux Kustomization (infra, depends on onepassword)
```

The `ClusterExternalSecret` targets namespaces with label `cluster-secrets: "true"` and reads from 1Password item `cluster-secrets` (a single item per cluster, with all 15 variables).

**Item naming:** Use `cluster-secrets` as the 1Password item name. Each cluster has its own 1Password vault (via separate service account scoping), so the same item name resolves to different values per cluster.

**Alternative if sharing a vault:** Use `cluster-${CLUSTER_NAME}` but this requires the ExternalSecret to support Flux substitution, which adds complexity (the ExternalSecret is a child of a Flux Kustomization that would need `substituteFrom` -- but we can't use cluster-secrets to create cluster-secrets).

**Simpler alternative:** Use the root ks.yaml's `postBuild.substitute` to inject `CLUSTER_NAME` into the child Kustomization's `postBuild.substitute`. The child Kustomization then substitutes `${CLUSTER_NAME}` in the ExternalSecret manifest. This works because:
1. Root ks.yaml builds kustomize output (includes child ks.yaml definitions)
2. Root postBuild substitutes `${CLUSTER_NAME}` in child ks.yaml text
3. Child ks.yaml gets `CLUSTER_NAME: "3226"` in its own `postBuild.substitute`
4. Child builds kustomize output (ExternalSecret YAML)
5. Child postBuild substitutes `${CLUSTER_NAME}` in ExternalSecret
6. ExternalSecret reads from 1Password item `cluster-3226`

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
  postBuild:
    substitute:
      CLUSTER_NAME: "${CLUSTER_NAME}"    # Inherited from root ks.yaml
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: external-secrets
  wait: true
```

#### Step 1.5: Add namespace labels

Add `cluster-secrets: "true"` label to the 10 namespaces that need cluster-secrets:

```
cert-manager, database, default, external-secrets, flux-system,
identity, kube-system, kubevirt, media, network
```

#### Step 1.6: Remove sops component

- Remove `- ../../components/sops` line from all 10 namespace `kustomization.yaml` files
- Delete `kubernetes/components/sops/cluster-secrets.sops.yaml`
- Delete `kubernetes/components/sops/kustomization.yaml`
- If `kubernetes/components/sops/` directory is empty, delete it

#### Step 1.7: Migrate other SOPS secrets to ExternalSecrets

For each of these, create an ExternalSecret that reads from 1Password:

| Current SOPS file | 1Password item | ExternalSecret location |
|-------------------|---------------|------------------------|
| `cert-manager/cert-manager/app/secret.sops.yaml` | `cloudflare` | `cert-manager/cert-manager/app/externalsecret.yaml` |
| `network/cloudflare-dns/app/secret.sops.yaml` | `cloudflare` | `network/cloudflare-dns/app/externalsecret.yaml` |
| `network/cloudflare-tunnel/app/secret.sops.yaml` | `cloudflare-tunnel` | `network/cloudflare-tunnel/app/externalsecret.yaml` |

Delete the SOPS files after creating the ExternalSecrets. Update each app's `app/kustomization.yaml` to reference the ExternalSecret instead of the SOPS secret.

**flux-instance webhook secret:** Keep as SOPS for now (low priority, shared across clusters).

#### Step 1.8: Update external-secrets kustomization

```yaml
# kubernetes/apps/external-secrets/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: external-secrets

components:
  - ../../components/alerts
  # REMOVED: ../../components/sops

resources:
  - ./namespace.yaml
  - ./external-secrets/ks.yaml
  - ./onepassword/ks.yaml
  - ./cluster-secrets/ks.yaml      # NEW
  - ./discord-webhook/ks.yaml
```

#### Step 1.9: Update failover.yaml workflow

The GitHub Action `failover.yaml` updates `SUSPEND_DEFAULT` in root ks.yaml files. It now also needs to update `CLUSTER_NAME` (or it's already set correctly and doesn't change during failover). Verify the workflow handles the new `postBuild.substitute` fields correctly.

### Phase 2: Testing (before merge to main)

#### CI Tests (automated)

| Test | Trigger | What it validates |
|------|---------|-------------------|
| `flux-local.yaml` | PR to main | Kustomize builds succeed, Flux diff shows expected changes |
| `e2e.yaml` | PR to main | Template pipeline works (init, configure) with test configs |
| `renovate-config.yaml` | If `.renovaterc.json5` changed | Renovate config valid |

**Expected `flux-local` diff output:** Should show:
- New `cluster-secrets` Kustomization and ClusterExternalSecret
- Removed SOPS cluster-secrets Secret from all namespaces
- New ExternalSecrets replacing SOPS secrets
- Updated ClusterSecretStore (SDK provider)
- Removed Connect server HelmRelease
- flux-instance path change (already in branch)
- New namespace labels

#### Manual Tests (require cluster access)

**Test 1: Verify current cluster-secrets state**
```bash
# Check what's actually in the cluster (not git)
kubectl -n flux-system get secret cluster-secrets -o json | jq '.data | keys'
kubectl -n cert-manager get secret cluster-secrets -o json | jq '.data | keys'
kubectl -n kube-system get secret cluster-secrets -o json | jq '.data | keys'
```
This confirms whether the 15 variables are actually populated in the cluster (they likely are from the last `task configure` run, even though git is stale).

**Test 2: Test SDK connectivity**
```bash
# Create a test ExternalSecret to validate SDK works
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: test-sdk
  namespace: default
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: test-sdk-secret
  dataFrom:
    - extract:
        key: cluster-3226
EOF

# Verify it synced
kubectl -n default get externalsecret test-sdk
kubectl -n default get secret test-sdk-secret -o json | jq '.data | keys'

# Cleanup
kubectl -n default delete externalsecret test-sdk
kubectl -n default delete secret test-sdk-secret
```

**Test 3: Dry-run Flux reconciliation**
```bash
# Preview what Flux would change
flux diff kustomization cluster-apps --path ./kubernetes/apps

# Or with flux-local CLI
flux-local diff kustomization --path kubernetes/flux/3226 --all-namespaces
```

**Test 4: Validate kustomize builds**
```bash
# Build all namespaces without sops component
kustomize build kubernetes/apps/cert-manager/
kustomize build kubernetes/apps/flux-system/
kustomize build kubernetes/apps/kube-system/
kustomize build kubernetes/apps/network/
# ... (all 10 namespaces that had sops component)
```

**Test 5: Verify ExternalSecret targeting**
```bash
# Check namespace labels
kubectl get ns -l cluster-secrets=true
# Should show: cert-manager, database, default, external-secrets, flux-system,
#              identity, kube-system, kubevirt, media, network
```

### Phase 3: Post-merge cleanup (follow-up PR)

After merge, monitor for ~24 hours, then:

| Step | Action | Validation |
|------|--------|------------|
| 3.1 | Verify Flux switched to new path | `kubectl -n flux-system get kustomization cluster-apps -o yaml \| grep kubernetes/flux` shows `kubernetes/flux/3226` |
| 3.2 | Remove `kubernetes/flux/cluster/` | Delete deprecated copy |
| 3.3 | Remove `kubernetes/components/sops/` | If not already deleted (may still have alertmanager component) |
| 3.4 | Update CLAUDE.md | Remove references to sops component, update secrets architecture |
| 3.5 | Update bootstrap docs | Reflect new SDK-based bootstrap flow |

---

## Post-Merge Monitoring Runbook

### Immediate (first 10 minutes)

```bash
# Watch Flux reconciliation
flux get ks -A -w

# Check for errors
flux logs --all-namespaces --level=error

# Verify cluster-secrets created by ESO
kubectl -n flux-system get externalsecret
kubectl -n flux-system get secret cluster-secrets -o json | jq '.data | keys'
```

### First hour

```bash
# Verify all ExternalSecrets synced
kubectl get externalsecret -A | grep -v SecretSynced  # Should be empty

# Verify critical infrastructure
cilium status
kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}'  # Should match CLUSTER_DNS_ADDR
kubectl -n network get svc -l gateway.envoyproxy.io/owning-gateway-name  # Check LB IPs

# Verify Cloudflare tunnel
kubectl -n network logs deploy/cloudflare-tunnel --tail=20

# Verify Envoy Gateway
kubectl -n network get gateway
```

### Next 24 hours

```bash
# Monitor Flux
flux get ks -A | grep -v "Applied\|True"  # Should be empty

# Check flux-instance path transition
kubectl -n flux-system get fluxinstance -o yaml | grep path

# Monitor ExternalSecret refreshes
kubectl get externalsecret -A -o custom-columns='NAME:.metadata.name,NS:.metadata.namespace,STATUS:.status.conditions[0].reason,AGE:.metadata.creationTimestamp'
```

---

## Rollback Plan

### If cluster-secrets is missing/wrong

```bash
# Emergency: manually create cluster-secrets from known values
kubectl -n flux-system create secret generic cluster-secrets \
  --from-literal=CLUSTER_NAME=3226 \
  --from-literal=SECRET_DOMAIN=<domain> \
  --from-literal=CLUSTER_POD_CIDR=172.30.0.0/16 \
  --from-literal=CLUSTER_SVC_CIDR=172.31.0.0/16 \
  --from-literal=CLUSTER_DNS_ADDR=172.31.0.10 \
  --from-literal=CLUSTER_API_ADDR=<api-vip> \
  --from-literal=CLUSTER_GATEWAY_ADDR=10.0.6.12 \
  --from-literal=CLUSTER_DNS_GATEWAY_ADDR=10.0.6.11 \
  --from-literal=CLOUDFLARE_GATEWAY_ADDR=10.0.6.13 \
  --from-literal=CLOUDFLARE_TOKEN=<token> \
  --from-literal=CLOUDFLARE_TUNNEL_ID=<tunnel-uuid> \
  --from-literal=NODE_CIDR=10.0.6.0/24 \
  --from-literal=CILIUM_LB_MODE=dsr \
  --from-literal=SUSPEND_DEFAULT=false \
  --dry-run=client -o yaml | kubectl apply -f -

# Repeat for each namespace that needs it:
for ns in cert-manager database default external-secrets identity kube-system kubevirt media network; do
  kubectl -n $ns create secret generic cluster-secrets --from-literal=... --dry-run=client -o yaml | kubectl apply -f -
done

# Force Flux reconciliation
task reconcile
```

### If Flux is deadlocked (path issue)

```bash
# Manually patch the FluxInstance to use the correct path
kubectl -n flux-system patch fluxinstance flux \
  --type=merge \
  -p '{"spec":{"sync":{"path":"kubernetes/flux/3226"}}}'

# Or manually update the root Kustomization
kubectl -n flux-system patch kustomization cluster-apps \
  --type=merge \
  -p '{"spec":{"path":"./kubernetes/apps"}}'
```

### Full revert

```bash
# Revert the merge commit
git revert <merge-commit-sha>
git push origin main

# Force Flux to pick up revert
task reconcile
```

---

## Risk Matrix

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Flux path deadlock | **Critical** -- all reconciliation stops | **Certain** without fix | Keep deprecated `kubernetes/flux/cluster/ks.yaml` |
| ESO SDK token invalid | **High** -- no secrets sync | Low (test beforehand) | Test SDK connectivity before merge |
| 1Password items missing keys | **High** -- missing substitutions | Low (validate beforehand) | Automated validation script |
| ClusterExternalSecret targeting wrong namespaces | **Medium** -- some namespaces miss secrets | Low (label-based, explicit) | Verify namespace labels before merge |
| Flux substitution ordering | **Medium** -- first reconciliation may fail | Medium (bootstrap race) | `dependsOn: onepassword` + `wait: true` on cluster-secrets |
| Connect removal breaks existing ExternalSecrets | **High** -- 43 ExternalSecrets fail | Low (SDK is drop-in) | Test SDK with existing ExternalSecrets first |
| Token rotation missed | **Medium** -- secrets stop refreshing | Low (90-day window) | Set up n8n workflow + calendar reminder |
| SOPS age key mismatch for usny01 | **Medium** -- can't decrypt bootstrap secrets | Medium (new cluster) | Generate age key during `task init CLUSTER=usny01` |

---

## Dependency Graph

```
Phase 0 (manual)
├── Create 1Password service account
├── Create 1Password items (cluster-3226, cluster-usny01, cloudflare, etc.)
└── Test SDK connectivity

Phase 1 (code changes, this branch)
├── Step 1.1: Fix Flux path deadlock (keep old path)
├── Step 1.2: Add CLUSTER_NAME to root ks.yaml
├── Step 1.3: Migrate 1Password Connect → SDK
│   ├── Update ClusterSecretStore
│   ├── Update bootstrap secret
│   └── Remove Connect deployment
├── Step 1.4: Create cluster-secrets ExternalSecret
│   ├── ClusterExternalSecret resource
│   └── Flux Kustomization (infra, depends on onepassword)
├── Step 1.5: Add namespace labels
├── Step 1.6: Remove sops component
│   ├── Remove from 10 namespace kustomizations
│   └── Delete component files
├── Step 1.7: Migrate SOPS secrets → ExternalSecrets
│   ├── cert-manager (Cloudflare API token)
│   ├── cloudflare-dns (Cloudflare API token)
│   └── cloudflare-tunnel (tunnel token)
├── Step 1.8: Update external-secrets kustomization
└── Step 1.9: Verify failover workflow

Phase 2 (testing)
├── CI: flux-local validation
├── CI: e2e template tests
├── Manual: Verify current cluster-secrets state
├── Manual: Test SDK connectivity
├── Manual: Dry-run Flux reconciliation
├── Manual: Validate kustomize builds
└── Manual: Verify namespace labels

MERGE TO MAIN

Phase 3 (post-merge cleanup)
├── Monitor Flux reconciliation (24h)
├── Verify path transition
├── Remove deprecated kubernetes/flux/cluster/
├── Update documentation
└── Set up token rotation
```

---

## Timeline Estimate

| Phase | Duration | Prerequisites |
|-------|----------|--------------|
| Phase 0 | 1 hour | 1Password admin access |
| Phase 1 | 2-3 hours | Phase 0 complete |
| Phase 2 | 1-2 hours | Phase 1 complete, cluster access |
| Merge | 5 minutes | Phase 2 passes |
| Phase 3 | 1 hour (+ 24h monitoring) | Merge complete |

---

## References

- [1Password SDK Migration](1password-sdk-migration.md) -- Detailed comparison and migration plan
- [Multi-Cluster Architecture](multi-cluster.md) -- Original design decisions
- [Flux CD Variable Substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
- [External Secrets ClusterExternalSecret](https://external-secrets.io/latest/api/clusterexternalsecret/)
- [Flux CD FAQ: Kustomization dependencies](https://fluxcd.io/flux/faq/#how-do-i-resolve-a-kustomization-dependency)
