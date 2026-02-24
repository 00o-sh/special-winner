# Multi-Cluster Migration Task List

Track of work needed to make the multi-cluster failover architecture fully functional.

## Problems Identified

### 1. Hardcoded NAS hostname (`nas.3226texas.com`)

Each site has its own NAS:
- **3226 (Texas)**: `nas.3226texas.com`
- **usny01 (Rochelle)**: `nas.2rochelle.com`

Currently, `nas.3226texas.com` is hardcoded in **20+ locations** across the codebase — NFS mounts, StorageClass definitions, observability scrape targets, MutatingAdmissionPolicies, and kustomization patches. None of these go through the Jinja2 template system or Flux variable substitution.

**Affected files:**
- `kubernetes/apps/kube-system/csi-driver-nfs/app/helmrelease.yaml` — `nfs-fast` StorageClass
- `kubernetes/apps/media/{plex,bazarr,radarr,sonarr,qbittorrent,qui}/app/helmrelease.yaml` — media NFS mounts
- `kubernetes/apps/volsync-system/garage/app/helmrelease.yaml` — Garage data/meta storage
- `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml` — Kopia repository storage
- `kubernetes/apps/volsync-system/kustomization.yaml` — NFS patches for maintenance/mover jobs
- `kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml` — NFS injection into mover pods
- `kubernetes/apps/volsync-system/volsync/maintenance/mutatingadmissionpolicy.yaml` — NFS injection into maintenance pods
- `kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfig.yaml` — node_exporter/smartctl targets
- `kubernetes/apps/observability/blackbox-exporter/lan/probes.yaml` — ICMP/TCP probes
- `kubernetes/apps/observability/silence-operator/silences/silences.yaml` — alert silence matchers
- `kubernetes/apps/network/unifi-dns/app/helmrelease.yaml` — `UNIFI_HOST: https://10.0.6.1` (also site-specific)

### 2. Flux suspension does NOT stop workloads — deeper than just DNS

**This is the most fundamental issue.** Flux `suspend: true` stops reconciliation but does **NOT** delete deployed Kubernetes resources. When a cluster transitions from active → standby:

- **Pods keep running** — Deployments still have their replicas, apps are still serving traffic
- **Services keep their LoadBalancer IPs** — Cilium keeps the IPs assigned
- **HTTPRoutes still exist** — Envoy Gateway still routes traffic
- **DNSEndpoints still exist** — DNS records are actively maintained
- **k8s-gateway still resolves apps** — it watches live HTTPRoute objects, which persist
- **unifi-dns still maintains records** — `policy: sync` keeps records alive because source objects exist

The expected DNS fallback path (NXDOMAIN → public DNS → Cloudflare tunnel → active cluster) **never triggers** because:
1. k8s-gateway sees HTTPRoutes and responds with the local gateway IP (not NXDOMAIN)
2. unifi-dns sees Services/HTTPRoutes/DNSEndpoints and keeps records on the Unifi controller
3. Everything is functionally still active — just frozen from git updates

**The failover only "works" for clusters bootstrapped as standby from day one** (resources never deployed). For active→standby transitions, `suspend: true` is effectively a no-op for running workloads.

**Root cause:** `prune: true` only runs during active reconciliation. When a Kustomization is suspended, pruning stops — resources are frozen in place forever.

**What's actually needed:** A mechanism that goes beyond Flux suspension — either scaling deployments to 0, deleting non-infra resources, or restructuring the failover to actively tear down workloads on the old cluster.

### 3. Volsync backups stored on NFS (not replicable across sites)

Volsync uses Kopia with a **filesystem** backend (`KOPIA_REPOSITORY: filesystem:///repository`) mounted via NFS to `nas.3226texas.com:/mnt/Speed/VolsyncKopia`. This NFS share is only accessible from the 3226 site.

**Current backup chain:**
1. Volsync component ExternalSecret creates `${APP}-volsync-secret` with `KOPIA_REPOSITORY: filesystem:///repository`
2. `volsync-mover-nfs` MutatingAdmissionPolicy injects NFS volume mount into every Volsync mover Job
3. `volsync-system/kustomization.yaml` patches maintenance CronJobs and backup Jobs to mount the same NFS path
4. Kopia server (`volsync-system/kopia/`) also mounts NFS at `/repository` for the web UI

**Impact:** After failover to usny01, there are no backup snapshots available to restore from — the filesystem repository is on the 3226 NAS.

---

## PR Plan

### PR 1: Add cluster-specific variables to cluster-secrets and templates

**Goal:** Lay the foundation for parameterizing site-specific values.

**Changes:**
- Add new variables to `templates/config/kubernetes/components/sops/cluster-secrets.sops.yaml.j2`:
  - `NAS_HOSTNAME` — NAS server hostname (e.g., `nas.3226texas.com` or `nas.2rochelle.com`)
  - `NAS_STORAGE_PATH` — Base NFS path for fast storage (e.g., `/mnt/Speed`)
  - `NAS_MEDIA_PATH` — NFS path for media (e.g., `/mnt/Rust/Media`)
  - `UNIFI_HOST` — Unifi controller URL (e.g., `https://10.0.6.1`)
- Add corresponding variables to the cluster.yaml schema/samples (`.github/tests/public.yaml`, `.github/tests/private.yaml`)
- Add the variables to CLAUDE.md documentation

**Dependencies:** None
**Risk:** Low — additive only, no behavior change

---

### PR 2: Parameterize all hardcoded NFS and site-specific references

**Goal:** Replace every hardcoded `nas.3226texas.com` and site-specific value with Flux `${VARIABLE}` substitution.

**Changes:**
- `kubernetes/apps/kube-system/csi-driver-nfs/app/helmrelease.yaml`: `server: ${NAS_HOSTNAME}`, `share: ${NAS_STORAGE_PATH}/Kubernetes`
- `kubernetes/apps/media/*/app/helmrelease.yaml` (6 files): `server: ${NAS_HOSTNAME}`, `path: ${NAS_MEDIA_PATH}`
- `kubernetes/apps/volsync-system/garage/app/helmrelease.yaml`: `server: ${NAS_HOSTNAME}`
- `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml`: `server: ${NAS_HOSTNAME}`
- `kubernetes/apps/volsync-system/kustomization.yaml`: `server: ${NAS_HOSTNAME}`
- `kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml`: NAS hostname in CEL expression
- `kubernetes/apps/volsync-system/volsync/maintenance/mutatingadmissionpolicy.yaml`: NAS hostname in CEL expression
- `kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfig.yaml`: scrape targets
- `kubernetes/apps/observability/blackbox-exporter/lan/probes.yaml`: probe targets
- `kubernetes/apps/observability/silence-operator/silences/silences.yaml`: silence matchers
- `kubernetes/apps/network/unifi-dns/app/helmrelease.yaml`: `UNIFI_HOST`
- Ensure all parent ks.yaml files have `substituteFrom: cluster-secrets` where needed

**Note on MutatingAdmissionPolicies:** These use CEL expressions, not YAML. The NAS hostname is a string literal in the CEL expression. These will need the hostname injected differently — either via a ConfigMap/Secret reference or by moving these to Jinja2 templates.

**Dependencies:** PR 1
**Risk:** Medium — touches many files, needs careful validation with `task configure`

---

### PR 3: Migrate Volsync from Kopia-filesystem (NFS) to Kopia-S3 (Garage)

**Goal:** Volsync backup repository moves from NFS-mounted filesystem to Garage S3 API. Backups are no longer tied to a specific NAS.

**Changes:**
- Update Volsync component ExternalSecret (`kubernetes/components/volsync/externalsecret.yaml`):
  - Change from `KOPIA_REPOSITORY: filesystem:///repository` + `KOPIA_FS_PATH: /repository`
  - To S3 config: `KOPIA_S3_ENDPOINT`, `KOPIA_S3_BUCKET`, `KOPIA_S3_ACCESS_KEY_ID`, `KOPIA_S3_SECRET_ACCESS_KEY`, etc.
  - Add Garage S3 credentials to 1Password `volsync-template` item
- Remove `volsync-mover-nfs` MutatingAdmissionPolicy (`kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml`) — the NFS repository volume injection is no longer needed since Kopia talks to S3 over HTTP
- Remove NFS patches from `kubernetes/apps/volsync-system/kustomization.yaml` — same reason
- Remove maintenance NFS MutatingAdmissionPolicy (`kubernetes/apps/volsync-system/volsync/maintenance/mutatingadmissionpolicy.yaml`)
- Update Kopia server (`kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml`):
  - Change `repository.config` storage type from `filesystem` to `s3`
  - Remove NFS persistence mount, add S3 config
- Update KopiaMaintenance resource if needed
- Create Garage S3 bucket for Volsync (or configure auto-bucket creation)

**Data migration:** Existing backups on NFS will not be accessible via S3. Options:
- Accept a clean start (new backup baseline after migration)
- Use `kopia repository sync-to` to migrate existing snapshots to S3

**Dependencies:** PR 2 (so Garage hostname is parameterized)
**Risk:** High — changes the entire backup pipeline. Must validate backup and restore flows end-to-end.

---

### PR 4: Make Garage storage independent per cluster

**Goal:** Each cluster's Garage instance is self-contained, not dependent on a specific NAS.

**Changes:**
- `kubernetes/apps/volsync-system/garage/app/helmrelease.yaml`:
  - Change `data` and `meta` persistence from `type: nfs` to PVCs with `openebs-hostpath` StorageClass
  - This makes Garage's own storage local to the cluster nodes
- Update Garage `configuration.toml` if needed for replication settings
- Consider increasing `replication_factor` from 1 in preparation for multi-site

**Why not keep Garage on NFS?** Each site has a different NAS. Even with parameterized hostnames (PR 2), Garage data on site A's NAS isn't accessible from site B. Local storage + Garage replication is the path to cross-site availability.

**Dependencies:** PR 3 (Volsync already using Garage S3, not filesystem)
**Risk:** Medium — need to migrate existing Garage data or accept a fresh start. Garage's metadata and object data will move to openebs-hostpath volumes.

---

### PR 5: Set up Garage cross-site replication

**Goal:** Volsync backup data is available at both sites, enabling restore after failover.

**Changes:**
- Configure Garage for multi-node operation across sites:
  - Site A (3226) runs Garage node(s) with data on local storage
  - Site B (usny01) runs Garage node(s) with data on local storage
  - Garage's built-in replication syncs objects between sites
  - Set `replication_factor = 2` (one copy per site) or use Garage's zone-aware replication
- Requires site-to-site VPN connectivity for Garage RPC traffic (port 3901)
- Update Garage configuration for multi-node cluster layout (node IDs, RPC addresses)
- Alternative approach: external S3 sync (e.g., rclone CronJob) if Garage multi-site is too complex

**Dependencies:** PR 4 (Garage on local storage)
**Risk:** High — distributed storage across WAN. Needs careful testing of replication lag, split-brain scenarios, and network partition handling.

---

### PR 6: Fix failover — actually stop workloads on standby clusters

**Goal:** When a cluster transitions to standby, workloads actually stop running, DNS records are cleaned up, and LAN clients fall through to public DNS → Cloudflare tunnel → active cluster.

**The problem is bigger than DNS.** Flux `suspend: true` doesn't stop anything — pods keep running, services keep their IPs, DNS records persist. We need workloads to actually shut down on standby.

**Approach options (choose one or combine):**

**Option A: Scale-to-zero via Flux patch (instead of suspend)**
- Instead of `suspend: ${SUSPEND_DEFAULT}`, patch non-infra HelmReleases to override `replicas: 0` on all Deployments/StatefulSets
- Alternatively, use a Flux patch that deletes non-infra Kustomizations entirely (not suspend, but actual removal)
- Pros: workloads actually stop, Services lose endpoints, DNS records become stale and get cleaned up by external-dns
- Cons: more complex patch logic, HelmRelease values vary per app

**Option B: Use `prune: true` with Kustomization deletion (not suspension)**
- Instead of setting `suspend: true` on child Kustomizations, remove them entirely from the parent's path
- Use per-cluster app directories: `kubernetes/apps-3226/` vs `kubernetes/apps-usny01/` with symlinks to shared manifests
- Standby cluster's app directory is empty → Flux prunes all workload resources
- Pros: clean teardown, `prune: true` does the heavy lifting
- Cons: major architectural change, breaks single-path-for-all-clusters model

**Option C: Failover task actively scales down workloads (recommended starting point)**
- Extend `task failover` and the GitHub Action to run `kubectl` commands against the old cluster:
  1. Scale all non-infra Deployments/StatefulSets to 0 replicas
  2. Delete non-infra HTTPRoutes, DNSEndpoints, and LoadBalancer Services
  3. unifi-dns (if infra-labeled) sees resources disappear → `policy: sync` cleans up Unifi records
  4. k8s-gateway sees no HTTPRoutes → returns NXDOMAIN → DNS fallback works
- Pros: explicit, predictable, works with current architecture
- Cons: requires kubectl access to the old cluster (doesn't work if cluster is dead)
- For the "cluster is dead" case: records persist until the cluster comes back and is reconciled as standby

**Option D: Zone delegation + infra k8s-gateway (solves DNS, not workloads)**
- Make k8s-gateway infra-labeled (runs on all clusters)
- Configure Unifi to delegate `00o.sh` to k8s-gateway instead of using unifi-dns for per-app records
- k8s-gateway reads live from the API — but if HTTPRoutes still exist (suspension doesn't delete them), it still resolves them
- Only works if combined with Option A or C (something that actually removes the HTTPRoutes)
- Partial solution: solves DNS but doesn't address the fact that apps are still running

**Recommended approach:** Start with **Option C** (explicit scale-down in failover task) as the immediate fix. Then evaluate **Option A** (Flux-native scale-to-zero patches) as a more elegant long-term solution that doesn't require kubectl access during failover.

**Key insight for DNS cleanup:** Make `unifi-dns` infra-labeled regardless of approach. When workloads are scaled down or deleted (by any mechanism), unifi-dns with `policy: sync` will automatically clean up records from the Unifi controller. This is self-healing and doesn't require explicit DNS cleanup steps.

**Dependencies:** PR 2 (parameterized UNIFI_HOST)
**Risk:** High — fundamental change to failover behavior. Must test thoroughly:
- Verify workloads actually stop on standby
- Verify DNS records are cleaned up
- Verify LAN clients fall through to Cloudflare tunnel
- Verify failover back (standby → active) re-deploys everything correctly

---

## Implementation Order

```
PR 1 (variables)
  └→ PR 2 (parameterize NFS/NAS)
       ├→ PR 3 (Volsync → S3)
       │    └→ PR 4 (Garage local storage)
       │         └→ PR 5 (Garage cross-site replication)
       └→ PR 6 (stale DNS fix)
```

PRs 3-5 form the "backup replication" chain.
PR 6 (failover fix) is independent of the backup work and can be done in parallel after PR 2.
PR 6 is arguably the most important — without it, failover doesn't actually work for active→standby transitions.

## Notes

- **Existing backups:** Moving from filesystem to S3 means a new backup baseline. Old NFS-based snapshots remain on the NAS but won't be accessible through the new pipeline.
- **Site-to-site VPN:** Required for Garage cross-site replication (PR 5) and for NFS access to the other site's NAS (if ever needed).
- **Testing:** Each PR should be validated with `task configure CLUSTER=3226` and `task configure CLUSTER=usny01` to ensure templates render correctly for both clusters.
- **MutatingAdmissionPolicies:** The CEL expressions in the Volsync MutatingAdmissionPolicies contain hardcoded NAS hostnames as string literals. These can't use Flux `${VARIABLE}` substitution since they're not processed by Flux. PR 3 removes these entirely (no NFS injection needed with S3 backend). For the interim (PR 2), these may need to become Jinja2 templates or reference a ConfigMap.
- **Flux suspend ≠ workload shutdown:** The current `SUSPEND_DEFAULT` mechanism only stops Flux from reconciling. It does NOT stop running pods, remove Services, delete HTTPRoutes, or clean up DNS records. Any failover strategy must account for this — either by adding an explicit teardown step or by changing the mechanism from suspension to actual resource removal/scaling.
