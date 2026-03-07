# CI/CD Pipelines

GitHub Actions workflows automate testing, validation, and deployment.

## Workflows

### flux-local.yaml

Validates Flux manifests on pull requests:

- Checks Flux configuration with `--enable-helm --all-namespaces`
- Generates diffs for HelmReleases and Kustomizations
- Triggers on `kubernetes/**` file changes

### e2e.yaml

End-to-end testing of the configuration pipeline:

- Runs `task init` and `task configure`
- Tests with sample configurations (public/private matrix)
- Validates with flux-local

### labeler.yaml

Automated PR labeling:

- **Area labels** based on changed file paths
- **Size labels**: xs (<10 lines), s (<30), m (<100), l (<500), xl (500+)
- Ignores markdown files for size calculation

### label-sync.yaml

Synchronizes GitHub labels from `.github/labels.yaml`:

- Triggered on pushes to main
- Deletes undefined labels
- Maintains consistent labeling

### label-generate.yaml

Auto-generates label configuration:

- Updates `.github/labels.yaml` and `.github/labeler.yaml`
- Keeps labels in sync with namespace/directory changes

### image-pull.yaml

Pre-pulls container images to cluster nodes:

- Extracts images from Flux manifests on PRs
- Compares images between PR and main branch
- Pulls new images via Talosctl
- Runs on self-hosted runner (`special-winner-runner`)
- Max 4 parallel pulls

### schemas.yaml

CRD schema extraction and publishing:

- Scheduled daily
- Extracts CRD schemas via datreeio/crd-extractor
- Publishes to Cloudflare Pages (`kubernetes-schemas` project)
- Runs on self-hosted runner
- Enables IDE autocompletion for custom resources

### docs.yaml

Documentation site publishing:

- Builds MkDocs Material site
- Publishes to Cloudflare Pages (`special-winner-docs` project)
- Triggered on docs/ or mkdocs.yml changes

### renovate-config.yaml

Renovate configuration validation:

- Validates `.renovaterc.json5` on pull requests
- Runs `renovate-config-validator --strict`
- Only triggers when `.renovaterc.json5` is modified

### release.yaml

Repository release management.

## Self-Hosted Runners

Some workflows run on self-hosted runners with cluster access, managed by Actions Runner Controller (ARC) in the `actions-runner-system` namespace.

### Runner Scale Sets

| Scale Set | Organization | Min Runners | Max Runners | Storage |
|-----------|-------------|-------------|-------------|---------|
| `special-winner` | 00o-sh | - | - | - |
| `ambersecurityinc` | ambersecurityinc | 1 | 3 | 25Gi |

### Workflows Using Self-Hosted Runners

- `image-pull.yaml` -- Needs Talosctl for image pulling
- `schemas.yaml` -- Needs kubectl for CRD extraction

### Monitoring

An ARC Grafana dashboard is available for monitoring runner autoscaling metrics (counters, gauges, histograms) at the cluster's Grafana instance.

## Troubleshooting CI/CD

### flux-local Validation Fails

The most common PR failure. Check the workflow output for specific errors:

```sh
# Run flux-local locally to reproduce
flux-local test --enable-helm --all-namespaces

# Common issues:
# - Invalid YAML syntax in HelmRelease or Kustomization
# - Missing OCIRepository reference
# - Duplicate resource names in the same namespace
```

### image-pull Fails

This workflow runs on the self-hosted runner and needs cluster access:

1. Check that the `special-winner-runner` pods are running:

    ```sh
    kubectl -n actions-runner-system get pods
    ```

2. Verify Talosctl connectivity to nodes (the runner needs access to pull images)

3. If the runner is unavailable, the job will stay queued — check the Actions Runner Controller logs:

    ```sh
    kubectl -n actions-runner-system logs -l app.kubernetes.io/name=actions-runner-controller-gha-rs-controller
    ```

### schemas.yaml Fails

- Requires the self-hosted runner with `kubectl` access
- Check that CRDs are installed in the cluster
- Verify Cloudflare Pages deployment token is valid

### docs.yaml Fails

- Check for MkDocs build errors (broken links, invalid YAML frontmatter)
- Run locally to reproduce:

    ```sh
    pip install mkdocs-material
    mkdocs build --strict
    ```

### General Debugging Tips

- **View workflow logs**: Go to the Actions tab on GitHub, click the failed run
- **Re-run a failed job**: Use the "Re-run jobs" button in the Actions UI
- **Check runner availability**: Self-hosted runner jobs will queue if no runners are available
- **Concurrency**: Most workflows use concurrency groups to prevent duplicate runs — a new push will cancel the previous run
