# Multi-Cluster Migration — PR Prompts

Each section below is a self-contained prompt you can paste into a new Claude Code session to implement that PR. They are ordered by dependency chain.

---

## PR 1: Add cluster-specific variables to cluster-secrets and templates

```
## Task

Add new cluster-specific variables so that site-specific values (NAS hostname, storage paths, Unifi controller) can differ per cluster. This is additive only — no existing behavior changes.

## What to do

### 1. Add variables to the cluster-secrets template

Edit `templates/config/kubernetes/components/sops/cluster-secrets.sops.yaml.j2`.

Add these new variables after the existing `CILIUM_LB_MODE` line (before the BGP conditional block):

```yaml
  NAS_HOSTNAME: "#{ nas_hostname }#"
  NAS_STORAGE_PATH: "#{ nas_storage_path }#"
  NAS_MEDIA_PATH: "#{ nas_media_path }#"
  UNIFI_HOST: "#{ unifi_host }#"
```

### 2. Add defaults in the template plugin

Edit `templates/scripts/plugin.py`. In the section where defaults are set (look for `node_default_gateway`, `cilium_loadbalancer_mode`, etc.), add defaults:

```python
data.setdefault("nas_hostname", "")
data.setdefault("nas_storage_path", "/mnt/Speed")
data.setdefault("nas_media_path", "/mnt/Rust/Media")
data.setdefault("unifi_host", "")
```

Do NOT set a default for `nas_hostname` or `unifi_host` — they must be explicitly configured per cluster (empty string default is fine, it will fail loudly if not set).

### 3. Add to the CUE schema

Edit `.taskfiles/template/resources/cluster.schema.cue`. Add inside the `#Config` block:

```cue
nas_hostname: string & !=""
nas_storage_path?: *"/mnt/Speed" | string & !=""
nas_media_path?: *"/mnt/Rust/Media" | string & !=""
unifi_host: string & !=""
```

`nas_hostname` and `unifi_host` are required (no default). `nas_storage_path` and `nas_media_path` have defaults.

### 4. Add to test configs

Edit `.github/tests/public.yaml` — add:
```yaml
nas_hostname: "nas.example.com"
nas_storage_path: "/mnt/Speed"
nas_media_path: "/mnt/Rust/Media"
unifi_host: "https://10.10.10.1"
```

Edit `.github/tests/private.yaml` — add:
```yaml
nas_hostname: "nas.example.com"
unifi_host: "https://10.10.10.1"
# nas_storage_path: ""
# nas_media_path: ""
```

### 5. Add to cluster sample config

Edit `templates/config/cluster.sample.yaml` (or wherever the sample cluster.yaml lives). Add the new fields with comments explaining them.

### 6. Update CLAUDE.md

In the "Cluster-Specific Variables" table in CLAUDE.md, add rows for `NAS_HOSTNAME`, `NAS_STORAGE_PATH`, `NAS_MEDIA_PATH`, and `UNIFI_HOST`.

## Validation

Run `task configure` (it will use the test configs in CI). The new variables should appear in the rendered `kubernetes/components/sops/cluster-secrets.sops.yaml` output.

## Commit

Use semantic commit: `feat(kubernetes): add cluster-specific NAS and Unifi variables to cluster-secrets`
```

---

## PR 2: Parameterize all hardcoded NFS and site-specific references

```
## Task

Replace every hardcoded `nas.3226texas.com` and site-specific value in Kubernetes manifests with Flux `${VARIABLE}` substitution using the variables added in the previous PR (`NAS_HOSTNAME`, `NAS_STORAGE_PATH`, `NAS_MEDIA_PATH`, `UNIFI_HOST`).

## Context

The cluster-secrets Secret (deployed by Flux) provides these variables to all Kustomizations via `postBuild.substituteFrom`. Any YAML field in a HelmRelease values block or raw manifest that is processed by Flux Kustomize controller can use `${NAS_HOSTNAME}` syntax.

**IMPORTANT exception**: MutatingAdmissionPolicy resources use CEL expressions. CEL string literals cannot use Flux `${VARIABLE}` substitution because they are not processed by Flux — they are raw Kubernetes resources evaluated by the API server. For these, we need a different approach (see below).

## Files to change

### Simple substitutions (NFS server hostname)

In each file below, replace `nas.3226texas.com` with `${NAS_HOSTNAME}`:

1. **`kubernetes/apps/kube-system/csi-driver-nfs/app/helmrelease.yaml`**
   - Find the `nfs-fast` StorageClass `server:` field
   - Also parameterize the `share:` path if it starts with `/mnt/Speed` → `${NAS_STORAGE_PATH}/Kubernetes`

2. **Media apps** (6 files) — find `server: nas.3226texas.com` and replace with `${NAS_HOSTNAME}`:
   - `kubernetes/apps/media/plex/app/helmrelease.yaml`
   - `kubernetes/apps/media/bazarr/app/helmrelease.yaml`
   - `kubernetes/apps/media/radarr/app/helmrelease.yaml`
   - `kubernetes/apps/media/sonarr/app/helmrelease.yaml`
   - `kubernetes/apps/media/qbittorrent/app/helmrelease.yaml`
   - `kubernetes/apps/media/qui/app/helmrelease.yaml`

   Also check NFS paths — if they reference `/mnt/Rust/Media`, replace with `${NAS_MEDIA_PATH}`.
   If they reference `/mnt/Speed/...`, replace the `/mnt/Speed` portion with `${NAS_STORAGE_PATH}`.

3. **Volsync/Garage** — replace `nas.3226texas.com` with `${NAS_HOSTNAME}`:
   - `kubernetes/apps/volsync-system/garage/app/helmrelease.yaml` (data and meta NFS mounts, lines ~132-140)
   - `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml` (repository NFS mount, line ~115)

   Also parameterize the NFS paths (replace `/mnt/Speed` prefix with `${NAS_STORAGE_PATH}`).

4. **Volsync kustomization patches** — `kubernetes/apps/volsync-system/kustomization.yaml`:
   - Two patches inject NFS volumes into CronJobs and Jobs
   - Replace `server: nas.3226texas.com` with `server: ${NAS_HOSTNAME}`
   - Replace `path: /mnt/Speed/VolsyncKopia` with `path: ${NAS_STORAGE_PATH}/VolsyncKopia`

5. **Observability**:
   - `kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfig.yaml` — find NAS-related scrape targets and parameterize
   - `kubernetes/apps/observability/blackbox-exporter/lan/probes.yaml` — find NAS probe targets and parameterize
   - `kubernetes/apps/observability/silence-operator/silences/silences.yaml` — find NAS matchers and parameterize

6. **Unifi DNS** — `kubernetes/apps/network/unifi-dns/app/helmrelease.yaml`:
   - Find `UNIFI_HOST: https://10.0.6.1` (or similar hardcoded IP)
   - Replace with `UNIFI_HOST: ${UNIFI_HOST}`

### MutatingAdmissionPolicy files (CEL — cannot use Flux substitution)

These two files have `nas.3226texas.com` as a string literal inside CEL expressions:

- `kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml` (line ~111: `server: "nas.3226texas.com"`)
- `kubernetes/apps/volsync-system/volsync/maintenance/mutatingadmissionpolicy.yaml` (line ~47: `server: "nas.3226texas.com"`)

**Approach**: Convert these to Jinja2 templates so the NAS hostname is rendered at `task configure` time:

1. Rename each file to add `.j2` extension:
   - `mutatingadmissionpolicy.yaml` → `mutatingadmissionpolicy.yaml.j2`
2. Replace the hardcoded hostname with Jinja2 variable:
   - `server: "nas.3226texas.com"` → `server: "#{ nas_hostname }#"`
   - `path: "/mnt/Speed/VolsyncKopia"` → `path: "#{ nas_storage_path }#/VolsyncKopia"`
3. Move/symlink the `.j2` files into the templates directory structure so `makejinja` picks them up:
   - Source: `templates/config/kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml.j2`
   - Output: `kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml`
   - Check `makejinja.toml` for the input/output path mapping — the templates go in `templates/config/` or `templates/overrides/`
4. Add the rendered output files to `.gitignore` (they're generated, like talos clusterconfig)
   - Or alternatively, just commit the rendered output and note it's generated (check existing patterns)

### Ensure substituteFrom is set

Verify that every parent ks.yaml for the affected namespaces includes `cluster-secrets` in its `postBuild.substituteFrom`. The root `kubernetes/flux/*/ks.yaml` already has `postBuild.substitute` but child Kustomizations may also need `substituteFrom`:

Check these namespace ks.yaml files and add if missing:
```yaml
spec:
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
```

Files to check:
- `kubernetes/apps/kube-system/csi-driver-nfs/ks.yaml`
- `kubernetes/apps/media/*/ks.yaml`
- `kubernetes/apps/volsync-system/*/ks.yaml`
- `kubernetes/apps/observability/*/ks.yaml`
- `kubernetes/apps/network/unifi-dns/ks.yaml`

## How to find all occurrences

Run: `grep -r "nas.3226texas.com" kubernetes/` and `grep -r "nas.3226texas.com" templates/`
Also: `grep -r "10.0.6.1" kubernetes/apps/network/unifi-dns/`

Every match should be addressed by this PR.

## Validation

After making changes, verify with: `task configure CLUSTER=3226`
The rendered output should have the actual hostnames substituted in.

## Commit

Use semantic commit: `feat(kubernetes): parameterize NAS hostname and site-specific values for multi-cluster`
```

---

## PR 3: Migrate Volsync from Kopia-filesystem (NFS) to Kopia-S3 (Garage)

```
## Task

Move the Volsync backup repository from NFS-mounted Kopia filesystem to Garage S3 API. After this change, Volsync mover jobs talk to Garage over HTTP instead of mounting NFS directly. This makes backups accessible from any cluster that can reach the Garage S3 endpoint.

## Context

### Current architecture
- Volsync component ExternalSecret creates secrets with `KOPIA_REPOSITORY: filesystem:///repository`
- A MutatingAdmissionPolicy (`volsync-mover-nfs`) injects an NFS volume mount into every Volsync mover Job
- A kustomization patch in `kubernetes/apps/volsync-system/kustomization.yaml` also injects NFS volumes into maintenance CronJobs and backup/restore Jobs
- A second MutatingAdmissionPolicy (`kopia-maintenance-nfs`) injects NFS into Kopia maintenance Jobs
- Kopia server (`volsync-system/kopia/`) mounts NFS at `/repository` for the web UI
- All of this depends on `nas.3226texas.com:/mnt/Speed/VolsyncKopia` being reachable

### Target architecture
- Volsync mover jobs use Kopia's S3 backend to talk to Garage at `garage-s3.volsync-system.svc.cluster.local:3900` (or the cluster-internal service)
- No NFS volume injection needed — remove both MutatingAdmissionPolicies for NFS
- No kustomization NFS patches needed — remove from `kubernetes/apps/volsync-system/kustomization.yaml`
- Kopia server uses S3 backend for its repository config
- Garage S3 credentials come from 1Password via ExternalSecret

## Files to change

### 1. Volsync component ExternalSecret

**File**: `kubernetes/components/volsync/externalsecret.yaml`

Change the template data from filesystem to S3:

**Current:**
```yaml
template:
  data:
    KOPIA_FS_PATH: /repository
    KOPIA_PASSWORD: "{{ .KOPIA_PASSWORD }}"
    KOPIA_REPOSITORY: filesystem:///repository
```

**New:**
```yaml
template:
  data:
    KOPIA_PASSWORD: "{{ .KOPIA_PASSWORD }}"
    AWS_ACCESS_KEY_ID: "{{ .GARAGE_S3_ACCESS_KEY_ID }}"
    AWS_SECRET_ACCESS_KEY: "{{ .GARAGE_S3_SECRET_ACCESS_KEY }}"
    KOPIA_S3_ENDPOINT: "garage.volsync-system.svc.cluster.local:3900"
    KOPIA_S3_BUCKET: volsync
    KOPIA_S3_REGION: USTX01
    KOPIA_S3_DISABLE_TLS: "true"
```

Note: The 1Password item `volsync-template` will need `GARAGE_S3_ACCESS_KEY_ID` and `GARAGE_S3_SECRET_ACCESS_KEY` fields added (user must do this manually in 1Password). The `KOPIA_PASSWORD` field already exists.

Check Kopia docs / Volsync docs for the exact env var names for S3. Kopia may use `KOPIA_S3_*` env vars or it may use `AWS_*` env vars. Verify by checking Kopia source or docs.

### 2. Remove volsync-mover-nfs MutatingAdmissionPolicy

**File**: `kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml`

This file contains two MutatingAdmissionPolicies:
- `volsync-mover-jitter` — KEEP this (adds random jitter to backup timing)
- `volsync-mover-nfs` — REMOVE this (injects NFS volume mount)

Remove the `volsync-mover-nfs` policy and its binding (the last two YAML documents in the file, starting around line 56).

### 3. Remove kopia-maintenance-nfs MutatingAdmissionPolicy

**File**: `kubernetes/apps/volsync-system/volsync/maintenance/mutatingadmissionpolicy.yaml`

This entire file is the `kopia-maintenance-nfs` policy. Delete the file entirely.

Update the kustomization.yaml in the same directory to remove the reference to this file.

### 4. Remove NFS patches from volsync-system kustomization

**File**: `kubernetes/apps/volsync-system/kustomization.yaml`

Remove both patch blocks:
- The patch targeting `CronJob` named `kopia-maint-daily-.*` (lines ~12-43)
- The patch targeting `Job` named `volsync-(src|dst)-.*` (lines ~44-76)

Keep the `components:`, `resources:`, and any non-NFS patches.

### 5. Update Kopia server to use S3 backend

**File**: `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml`

**repository.config** — change the storage type (in the configMap `config` → `repository.config`):

**Current:**
```json
{
  "storage": {
    "type": "filesystem",
    "config": {
      "path": "/repository"
    }
  },
  ...
}
```

**New:**
```json
{
  "storage": {
    "type": "s3",
    "config": {
      "bucket": "volsync",
      "endpoint": "garage.volsync-system.svc.cluster.local:3900",
      "region": "USTX01",
      "doNotUseTLS": true
    }
  },
  ...
}
```

**Persistence** — remove the NFS repository mount:

Remove this block from `persistence:`:
```yaml
repository:
  type: nfs
  server: nas.3226texas.com
  path: /mnt/Speed/VolsyncKopia
  globalMounts:
    - path: /repository
```

**Secrets** — Kopia needs S3 credentials. Either:
- Add `envFrom` referencing a secret with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Or create a separate ExternalSecret for Kopia's S3 credentials

### 6. Update KopiaMaintenance if needed

Check `kubernetes/apps/volsync-system/volsync/maintenance/kopiamaintenance.yaml` — if it references NFS paths or filesystem-specific config, update accordingly.

### 7. Create Garage S3 bucket

Add a Job or init container that creates the `volsync` bucket in Garage. Or document that the user needs to create it manually via the Garage admin API:
```bash
garage bucket create volsync
garage key create volsync-key
garage bucket allow volsync --read --write --owner --key volsync-key
```

## Data migration note

Existing backups on NFS will NOT be accessible after this change. This is a clean start for the S3-backed repository. If the user wants to migrate existing snapshots, they can use `kopia repository sync-to` before cutting over, but that's a manual step outside this PR.

## Validation

1. After deploying, verify Volsync mover jobs start without NFS mount errors
2. Verify Kopia web UI at `kopia.00o.sh` connects to the S3 repository
3. Trigger a manual backup and verify it lands in Garage S3
4. Trigger a manual restore and verify data is recovered

## Commit

Use semantic commit: `feat(volsync): migrate backup repository from NFS filesystem to Garage S3`
```

---

## PR 4: Make Garage storage independent per cluster

```
## Task

Move Garage's own data and metadata storage from NFS to local PVCs (openebs-hostpath). Each cluster's Garage instance becomes self-contained — its data lives on the cluster nodes, not on a site-specific NAS.

## Context

Currently, Garage stores both data and metadata on NFS:
- `data` → `nas.3226texas.com:/mnt/Speed/Kubernetes/apps/garage/data`
- `meta` → `nas.3226texas.com:/mnt/Speed/Kubernetes/apps/garage/meta`

This means Garage on usny01 can't function because it can't reach the 3226 NAS. After this PR, each cluster runs a fully independent Garage instance on local storage.

## Files to change

### 1. Garage HelmRelease

**File**: `kubernetes/apps/volsync-system/garage/app/helmrelease.yaml`

Change the persistence section from NFS to PVCs:

**Current** (lines ~130-141):
```yaml
persistence:
  config:
    enabled: true
    type: configMap
    name: garage
    globalMounts:
      - path: /etc/garage.toml
        subPath: configuration.toml
  data:
    type: nfs
    server: nas.3226texas.com
    path: /mnt/Speed/Kubernetes/apps/garage/data
    globalMounts:
      - path: /data
  meta:
    type: nfs
    server: nas.3226texas.com
    path: /mnt/Speed/Kubernetes/apps/garage/meta
    globalMounts:
      - path: /meta
```

**New:**
```yaml
persistence:
  config:
    enabled: true
    type: configMap
    name: garage
    globalMounts:
      - path: /etc/garage.toml
        subPath: configuration.toml
  data:
    type: persistentVolumeClaim
    storageClass: openebs-hostpath
    accessMode: ReadWriteOnce
    size: 50Gi
    globalMounts:
      - path: /data
  meta:
    type: persistentVolumeClaim
    storageClass: openebs-hostpath
    accessMode: ReadWriteOnce
    size: 5Gi
    globalMounts:
      - path: /meta
```

Adjust sizes based on current usage. Check the bjw-s app-template chart docs for exact PVC syntax — it may use `existingClaim` or `spec` instead of top-level `storageClass`/`size`.

### 2. Garage configuration

**File**: `kubernetes/apps/volsync-system/garage/app/resources/configuration.toml`

Verify `data_dir` and `metadata_dir` paths match the mount points (`/data` and `/meta`). These should already be correct since the mount paths aren't changing.

Check if `replication_factor = 1` is still appropriate. For a single-node Garage (which is the case per cluster), it must stay at 1.

## Data migration note

Existing Garage data on NFS will not be migrated. If Volsync was already cut over to S3 (PR 3), the Garage bucket will need to be recreated. This is effectively a fresh Garage instance per cluster.

Steps after deploying:
1. Garage starts with empty local storage
2. Re-create the `volsync` bucket and access keys via Garage admin API
3. Update 1Password with new access keys if they changed
4. Volsync begins backing up to the new empty repository

## Validation

1. Verify Garage pod starts and is healthy (check `garage-api.00o.sh/health`)
2. Verify PVCs are created and bound
3. Verify Volsync can still write backups to Garage S3
4. Verify Kopia web UI still works

## Commit

Use semantic commit: `feat(volsync): migrate Garage storage from NFS to local PVCs`
```

---

## PR 5: Set up Garage cross-site replication

```
## Task

Configure Garage to replicate backup data across sites so that after failover, the standby cluster has access to all Volsync backup snapshots.

## Context

After PRs 3-4, each cluster has an independent Garage instance on local storage. Backups made on cluster 3226 are only on 3226's Garage. If 3226 fails, usny01's Garage has no data. This PR adds cross-site replication.

## Research needed first

Before implementing, research these questions:

1. **Garage multi-node across WAN**: Can Garage form a cluster across a site-to-site VPN? What are the latency requirements for its RPC protocol (port 3901)?

2. **Garage zone-aware replication**: Garage supports zone labels on nodes. With `replication_factor = 2` and two zones (one per site), Garage ensures one copy per zone. Is this production-ready?

3. **Alternative: rclone sync**: Instead of Garage clustering, would a CronJob running `rclone sync` between two independent Garage S3 instances be simpler and more reliable over WAN?

4. **Alternative: Kopia server-side replication**: Can Kopia itself be configured to replicate its repository to a second S3 endpoint?

## Approach A: Garage multi-site cluster

### Changes needed

1. **Garage configuration** — update `configuration.toml`:
   - Set `replication_factor = 2` (one copy per site)
   - Add zone configuration per node
   - Configure RPC endpoints to include the remote site's Garage

2. **Networking** — ensure port 3901 (Garage RPC) is routable over the site-to-site VPN between clusters

3. **Node discovery** — each Garage node needs to know the other site's node ID and address. This could be:
   - Static config via `bootstrap_peers`
   - DNS-based discovery

4. **Per-cluster Garage config** — the `configuration.toml` needs to differ per cluster (different `node_id`, different local address, same cluster). This may require making it a Jinja2 template or using Flux substitution.

## Approach B: rclone CronJob (simpler)

### Changes needed

1. **Create a CronJob** in `kubernetes/apps/volsync-system/garage/` that runs `rclone sync` between the local Garage S3 and the remote site's Garage S3
2. **Schedule**: every 6 hours or daily
3. **Credentials**: needs S3 access keys for both local and remote Garage instances
4. **Direction**: bidirectional sync or active→standby only

## Recommendation

Start with Approach B (rclone) as it's simpler, doesn't require Garage clustering, and works reliably over WAN with varying latency. Graduate to Approach A if the rclone approach proves too slow or introduces too much backup lag.

## Commit

Use semantic commit: `feat(volsync): add cross-site Garage backup replication`
```

---

## PR 6: Fix failover — actually stop workloads on standby clusters

```
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
```

---

## Dependency graph

```
PR 1 (add variables)
  └─▶ PR 2 (parameterize NFS/NAS references)
        ├─▶ PR 3 (Volsync → S3)
        │     └─▶ PR 4 (Garage local storage)
        │           └─▶ PR 5 (Garage cross-site replication)
        └─▶ PR 6 (fix failover workload shutdown)
```

PR 6 is the most impactful — without it, failover doesn't actually work for active→standby transitions. It can be started in parallel with PRs 3-5 once PR 2 lands.
