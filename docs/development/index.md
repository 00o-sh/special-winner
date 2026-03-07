# Development

Guides for developing and contributing to the cluster repository.

## Utility Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-apps.sh` | Main cluster bootstrap |
| `scripts/volsync-restore-all.sh` | Mass VolSync point-in-time restore for all 16 backed-up apps |
| `scripts/generate-labels.sh` | Auto-generate `.github/labels.yaml` and `.github/labeler.yaml` from directory structure |

## Documentation Site

The docs site at [docs.00o.sh](https://docs.00o.sh) is built with MkDocs Material from the `docs/` directory. To preview locally:

```sh
pip install mkdocs-material
mkdocs serve
```

Changes to `docs/` or `mkdocs.yml` on main are automatically published via the `docs.yaml` workflow.

## Pages

- [Template System](templates.md) -- Jinja2 configuration templating
- [CI/CD Pipelines](ci-cd.md) -- GitHub Actions workflows
- [Contributing](contributing.md) -- Conventions and guidelines
