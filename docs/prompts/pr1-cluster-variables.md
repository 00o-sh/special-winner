# PR 1: Add cluster-specific variables to cluster-secrets and templates

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
