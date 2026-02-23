# Multi-Cluster Architecture Research

> Researched 2026-02-22. Stack: Flux CD 2.7.5, Talos Linux 1.12.4, Kubernetes 1.34.0, Cilium 1.19.0, Cloudflare Tunnel.

## Recommendation: Single-Repo Active/Standby with Flux Substitution

Use a single Git repository to manage multiple Kubernetes clusters with per-cluster Flux entry points, variable substitution for cluster-specific values, and a `SUSPEND_DEFAULT` mechanism for active/standby failover.

## Problem Statement

The homelab started as a single-cluster deployment. As the infrastructure matured, several needs emerged:

1. **Disaster recovery** -- If the primary cluster fails, workloads should be recoverable on a second cluster with minimal manual intervention
2. **Geographic distribution** -- Ability to run clusters in different physical locations (e.g. US-NY-01)
3. **Zero-downtime failover** -- External DNS (Cloudflare) shouldn't need updating during failover
4. **GitOps consistency** -- All clusters should be managed from the same Git repository and share the same application definitions

## Approaches Considered

### Option 1: Separate Repositories per Cluster

Each cluster gets its own Git repository with its own Flux configuration.

**Pros:**

- Complete isolation between clusters
- Simple to understand
- No risk of one cluster's changes affecting another

**Cons:**

- Duplicate application manifests across repos (maintenance nightmare)
- Config drift between clusters over time
- No unified view of cluster state
- Difficult to coordinate failover

**Verdict:** Rejected. The duplication and drift risk outweigh the isolation benefits for a homelab with shared workloads.

### Option 2: Branch-per-Cluster

Each cluster watches a different Git branch (e.g. `cluster-3226`, `cluster-usny01`).

**Pros:**

- Single repo
- Clean separation of cluster state
- Cherry-pick changes between clusters

**Cons:**

- Merge conflicts when syncing shared app changes across branches
- Easy to forget to propagate changes
- Renovate PRs need to target multiple branches
- Flux doesn't natively support branch-based multi-cluster well

**Verdict:** Rejected. Branch management overhead is too high for the homelab use case.

### Option 3: Single Repo with Per-Cluster Flux Entry Points (Chosen)

All clusters share the same `kubernetes/apps/` manifests. Each cluster has:

- Its own Flux root Kustomization at `kubernetes/flux/<cluster>/ks.yaml`
- Its own config directory at `clusters/<cluster>/`
- Cluster-specific values injected via `${VARIABLE}` substitution from `cluster-secrets`

**Pros:**

- Single source of truth for all application definitions
- No duplication -- changes to apps automatically apply to all clusters
- Per-cluster customization via Flux variable substitution
- Clean failover mechanism via `SUSPEND_DEFAULT`
- Renovate PRs work across all clusters automatically
- CI/CD validates all clusters in one pass

**Cons:**

- Slightly more complex initial setup
- All clusters must be compatible with the same app manifests (solved by substitution)
- A bad merge could theoretically affect all clusters (mitigated by CI validation)

**Verdict:** Chosen. Best balance of simplicity, maintainability, and flexibility.

## Design Decisions

### Per-Cluster Directory Structure

```
clusters/<cluster-name>/
├── cluster.yaml           # Cluster config (CIDRs, domain, features)
├── nodes.yaml             # Node definitions
├── age.key                # SOPS encryption key
├── kubeconfig             # Cluster kubeconfig
├── cloudflare-tunnel.json # Shared tunnel credentials
├── github-deploy.key      # Flux deploy key
└── github-push-token.txt  # Webhook token
```

**Reasoning:** All per-cluster sensitive files are colocated and gitignored. This makes it easy to `task init CLUSTER=<name>` and have everything in one place. The `clusters/` top-level directory clearly separates per-cluster config from shared infrastructure.

### Flux Variable Substitution for Cluster-Specific Values

Rather than templating different manifests per cluster, we use Flux's built-in `postBuild.substituteFrom` to inject cluster-specific values at reconciliation time.

**Variables extracted to cluster-secrets:**

| Variable | Why | Example |
|----------|-----|---------|
| `CLUSTER_NAME` | App identity, logging | `3226` |
| `CLUSTER_POD_CIDR` | Cilium pod network | `172.30.0.0/16` |
| `CLUSTER_SVC_CIDR` | Cilium service network | `172.31.0.0/16` |
| `CLUSTER_DNS_ADDR` | CoreDNS cluster IP | `172.31.0.10` |
| `CLUSTER_API_ADDR` | Kubernetes API VIP | `10.0.6.10` |
| `CLUSTER_GATEWAY_ADDR` | Internal LB IP | `10.0.6.12` |
| `CLUSTER_DNS_GATEWAY_ADDR` | k8s-gateway LB IP | `10.0.6.11` |
| `CLOUDFLARE_GATEWAY_ADDR` | External LB IP | `10.0.6.13` |
| `NODE_CIDR` | Node subnet | `10.0.6.0/24` |
| `CILIUM_LB_MODE` | Cilium LB mode | `dsr` |
| `SUSPEND_DEFAULT` | Failover control | `false` |

**Reasoning:** These values were previously hardcoded in Helm values and Kubernetes manifests. Extracting them to `${VARIABLE}` substitution means the same manifest works across clusters with different network layouts. This is a core Flux feature, not a hack.

### Active/Standby Failover with SUSPEND_DEFAULT

**Mechanism:**

1. Each cluster's root `ks.yaml` sets `SUSPEND_DEFAULT` in `postBuild.substitute`
2. A Flux patch on the root Kustomization injects `suspend: ${SUSPEND_DEFAULT}` into all child Kustomizations
3. Infra apps are labeled `cluster.home/role: infra` and excluded from the patch
4. The `active-cluster` file at repo root is the source of truth

**Why not use Flux's built-in suspend?**

Flux's `suspend` field on individual Kustomizations would require editing every single `ks.yaml` during failover. The `SUSPEND_DEFAULT` approach uses a single variable that propagates to all non-infra workloads automatically.

**Why keep infra running on standby?**

The standby cluster needs Flux (to watch for failover), Cilium (networking), CoreDNS (DNS), cert-manager (certificate renewal), OpenEBS (storage), and External Secrets (secret sync). Without these, the cluster can't quickly resume workloads during failover.

### Shared Cloudflare Tunnel

Both clusters share the same Cloudflare tunnel credentials (`cloudflare-tunnel.json`). Only the active cluster runs `cloudflared`.

**Reasoning:** The Cloudflare tunnel ID is embedded in DNS CNAME records. By sharing the tunnel, failover doesn't require any DNS changes. The standby cluster's `cloudflared` pod is suspended via `SUSPEND_DEFAULT`, so there's no conflict. When failover occurs, the new active cluster starts `cloudflared` and Cloudflare routes traffic to it automatically.

### Task System with CLUSTER Parameter

All tasks accept `CLUSTER=<name>` (default: `3226`):

```sh
task init CLUSTER=usny01
task configure CLUSTER=usny01
task bootstrap:talos CLUSTER=usny01
task bootstrap:apps CLUSTER=usny01
task failover CLUSTER=usny01
```

**Reasoning:** The `CLUSTER` parameter drives the entire workflow. Tasks symlink the cluster's config files before running, so the template system and bootstrap scripts work without modification. Defaulting to `3226` preserves backward compatibility.

## Failover Methods

### Method 1: Local Task (Preferred)

```sh
task failover CLUSTER=usny01
git add -A && git commit -m "chore: failover to usny01" && git push
```

The task updates `active-cluster` and both root `ks.yaml` files. Push triggers Flux reconciliation.

### Method 2: Git-Only (CI Automated)

Edit `active-cluster` to contain `usny01`, commit, push. The `failover.yaml` GitHub Action detects the change and automatically updates both root `ks.yaml` files.

**Trade-off:** Method 1 is atomic (all changes in one commit). Method 2 requires two commits (your change + CI's change) but works from any Git client without task tooling.

## Alternatives Explored for Failover

### Argo CD ApplicationSets

Argo CD's ApplicationSets natively support multi-cluster with generators. However, this cluster uses Flux CD, and migrating to Argo CD for multi-cluster support would be a massive refactor with no other benefit.

### Flux Multi-Tenancy

Flux's multi-tenancy model (separate namespaces per tenant) could theoretically separate clusters. But this is designed for different teams sharing one cluster, not one team managing multiple clusters.

### External Orchestrator (Crossplane, Cluster API)

Tools like Crossplane or Cluster API manage cluster lifecycle externally. This is overkill for a 2-cluster homelab and adds significant complexity.

### Manual kubectl per Cluster

Simply switching `KUBECONFIG` and manually managing each cluster. This defeats the purpose of GitOps and doesn't provide automated failover.

## Implementation Summary

The implementation was done in three commits:

1. **Multi-cluster prep** -- Added `CLUSTER` variable to tasks, created `clusters/3226/` directory, converted hardcoded values to Flux `${VARIABLE}` substitution, renamed Flux entry point to `kubernetes/flux/3226/`

2. **Cluster usny01** -- Created `clusters/usny01/` directory and `kubernetes/flux/usny01/ks.yaml` with `SUSPEND_DEFAULT: "true"`

3. **Failover mechanism** -- Added `active-cluster` file, Flux patch for `SUSPEND_DEFAULT` injection, `cluster.home/role: infra` labels on 14 infra ks.yaml files, `failover.yaml` GitHub Action, `task failover` command

## References

- [Flux CD Multi-Tenancy](https://fluxcd.io/flux/installation/configuration/multitenancy/)
- [Flux CD Variable Substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) -- Base template
- [Talos Linux Cluster Discovery](https://www.talos.dev/v1.12/talos-guides/discovery/)
