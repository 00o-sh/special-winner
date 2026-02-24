# PR 6: Fix failover — actually stop workloads on standby clusters

## Task

Fix the fundamental problem: Flux `suspend: true` does NOT stop running workloads. Pods keep running, Services keep their LoadBalancer IPs, HTTPRoutes persist, DNS records stay alive. The expected DNS fallback path (NXDOMAIN → Cloudflare tunnel → active cluster) never triggers because everything is still running.

## Context

### Current failover mechanism
1. `active-cluster` file changes (or `task failover CLUSTER=usny01`)
2. GitHub Action updates `kubernetes/flux/*/ks.yaml` — active gets `SUSPEND_DEFAULT: "false"`, standby gets `"true"`
3. Root ks.yaml has a patch that applies `suspend: ${SUSPEND_DEFAULT}` to all child Kustomizations without `cluster.home/role: infra` label
4. Flux stops reconciling suspended Kustomizations but does NOT delete any deployed resources

### Why this fails for active→standby
- Pods keep their replicas — Deployments are untouched
- Services keep LoadBalancer IPs — Cilium doesn't release them
- HTTPRoutes still exist — Envoy Gateway still routes traffic
- k8s-gateway sees HTTPRoutes → resolves to local gateway IP (no NXDOMAIN)
- unifi-dns sees resources → keeps DNS records on Unifi controller
- Result: both clusters are "active" from a traffic perspective, but one is frozen from git updates

### What we need
When a cluster transitions to standby, non-infra workloads must actually stop: pods scaled to 0, Services lose endpoints, HTTPRoutes deleted, DNS records cleaned up.

## Recommended approach: Extend failover task + GitHub Action

### Phase 1: Scale-to-zero in failover (immediate fix)

**Extend `task failover`** in `Taskfile.yaml` to actively scale down workloads on the old cluster:

After updating `SUSPEND_DEFAULT` in ks.yaml files, add steps to:

1. Get the KUBECONFIG for the OLD (now-standby) cluster
2. Get all non-infra namespaces (everything except: cert-manager, flux-system, kube-system, openebs-system, external-secrets)
3. Scale all Deployments in those namespaces to 0 replicas
4. Scale all StatefulSets in those namespaces to 0 replicas
5. Delete all HTTPRoutes in those namespaces
6. Delete all DNSEndpoints in those namespaces (except infra ones)

```bash
# Infra namespaces to skip
INFRA_NS="cert-manager flux-system kube-system openebs-system external-secrets"

# Get all non-infra namespaces
for ns in $(kubectl --kubeconfig="$OLD_KUBECONFIG" get ns -o jsonpath='{.items[*].metadata.name}'); do
  echo "$INFRA_NS" | grep -qw "$ns" && continue

  # Scale deployments to 0
  kubectl --kubeconfig="$OLD_KUBECONFIG" -n "$ns" get deploy -o name | \
    xargs -r kubectl --kubeconfig="$OLD_KUBECONFIG" -n "$ns" scale --replicas=0

  # Scale statefulsets to 0
  kubectl --kubeconfig="$OLD_KUBECONFIG" -n "$ns" get sts -o name | \
    xargs -r kubectl --kubeconfig="$OLD_KUBECONFIG" -n "$ns" scale --replicas=0

  # Delete HTTPRoutes
  kubectl --kubeconfig="$OLD_KUBECONFIG" -n "$ns" delete httproutes --all

  # Delete DNSEndpoints
  kubectl --kubeconfig="$OLD_KUBECONFIG" -n "$ns" delete dnsendpoints --all
done
```

**Key detail**: The kubeconfig for each cluster lives at `clusters/<cluster-name>/kubeconfig`. The task needs to determine which cluster WAS active before the switch, then use that cluster's kubeconfig to scale down.

### Phase 2: Make unifi-dns infra (self-healing DNS cleanup)

**File**: `kubernetes/apps/network/unifi-dns/ks.yaml`

Add the infra label so unifi-dns runs on ALL clusters:
```yaml
metadata:
  labels:
    cluster.home/role: infra
```

**Why**: When workloads are scaled to 0 or HTTPRoutes are deleted (Phase 1), unifi-dns with `policy: sync` will automatically remove the stale DNS records from the Unifi controller. This is self-healing — no explicit DNS cleanup needed in the failover script.

Also consider making these infra:
- `kubernetes/apps/network/envoy-gateway/ks.yaml` — gateway should run everywhere for per-cluster DNS endpoints
- `kubernetes/apps/network/k8s-gateway/ks.yaml` — internal DNS should run everywhere

### Phase 3: Update GitHub Action

**File**: `.github/workflows/failover.yaml`

The GitHub Action currently only updates ks.yaml files. It can't run kubectl commands (no cluster access from GitHub-hosted runners). Options:

**Option A**: Add a second job that runs on the self-hosted runner (`special-winner-runner`) which HAS cluster access:
```yaml
scale-down:
  needs: failover
  runs-on: special-winner-runner
  steps:
    - name: Scale down old cluster
      run: |
        # Same kubectl commands as the task, using the appropriate kubeconfig
```

**Option B**: Keep the GitHub Action as-is (just updates ks.yaml) and rely on Flux to eventually reconcile. Add a Flux `postBuild` hook or a separate Kustomization that watches `SUSPEND_DEFAULT` and runs a scale-down Job when it changes to "true".

**Option C**: Create a Kubernetes CronJob or controller on each cluster that watches its own `SUSPEND_DEFAULT` value and self-scales-to-zero when it becomes "true". This is the most resilient option (works even if the failover task can't reach the cluster).

### Phase 4 (future): Flux-native scale-to-zero

Instead of external kubectl commands, modify the root ks.yaml patch to inject `replicas: 0` into HelmRelease values on standby clusters. This is more elegant but requires understanding each app's Helm values structure.

## Files to change (Phase 1 + 2)

1. `Taskfile.yaml` — extend the `failover` task
2. `kubernetes/apps/network/unifi-dns/ks.yaml` — add `cluster.home/role: infra` label
3. `kubernetes/apps/network/envoy-gateway/ks.yaml` — consider adding infra label
4. `kubernetes/apps/network/k8s-gateway/ks.yaml` — consider adding infra label
5. `.github/workflows/failover.yaml` — extend with scale-down job (if using self-hosted runner)
6. Update CLAUDE.md — document the new failover behavior

## Testing checklist

- [ ] `task failover CLUSTER=usny01` scales down workloads on 3226
- [ ] Pods reach 0/0 in non-infra namespaces on 3226
- [ ] HTTPRoutes are deleted on 3226
- [ ] k8s-gateway on 3226 returns NXDOMAIN for suspended apps
- [ ] unifi-dns removes stale records from Unifi controller
- [ ] LAN clients fall through to Cloudflare tunnel → usny01
- [ ] `task failover CLUSTER=3226` (fail back) — Flux unsuspends and redeploys everything on 3226
- [ ] After failback, workloads are healthy and DNS is restored

## Commit

Use semantic commit: `fix(kubernetes): actively stop workloads on standby clusters during failover`
