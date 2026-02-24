# PR 2: Parameterize all hardcoded NFS and site-specific references

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

**IMPORTANT**: Search both `kubernetes/` (committed manifests for running clusters) and `templates/` (Jinja2 templates for new clusters). Changes must be made in the actual manifest files under `kubernetes/`, not just in templates. Flux reads the committed manifests directly — templates are only used during `task configure` to generate files like `.sops.yaml` and talos configs.

## Validation

After making changes:
1. Run `task configure CLUSTER=3226` to verify template-rendered files still work
2. Re-run the grep searches above — there should be zero matches for hardcoded values
3. Verify `${VARIABLE}` substitution syntax is correct in all modified files (Flux will substitute at reconciliation time from `cluster-secrets`)

## Commit

Use semantic commit: `feat(kubernetes): parameterize NAS hostname and site-specific values for multi-cluster`
