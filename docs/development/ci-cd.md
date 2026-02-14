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

### release.yaml

Repository release management.

## Self-Hosted Runners

Some workflows run on `special-winner-runner` (self-hosted) with cluster access:

- `image-pull.yaml` -- Needs Talosctl for image pulling
- `schemas.yaml` -- Needs kubectl for CRD extraction

Runners are managed by Actions Runner Controller in the `actions-runner-system` namespace.
