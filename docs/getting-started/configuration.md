# Configuration

## Generate Config Files

```sh
task init
```

This creates `cluster.yaml`, `nodes.yaml`, `age.key`, and other configuration files from samples.

## Edit Configuration

Fill out the generated files using the comments as guidance:

- **`cluster.yaml`** -- Cluster-wide settings (domain, network CIDRs, feature flags)
- **`nodes.yaml`** -- Node definitions (hostnames, IPs, roles, disk paths)

## Render and Validate

```sh
task configure
```

This runs makejinja to render Jinja2 templates and validates the output.

## Template System

The configuration uses [makejinja](https://github.com/mirkolenz/makejinja) with custom Jinja2 delimiters to avoid YAML conflicts:

| Delimiter | Syntax | Standard Jinja2 |
|-----------|--------|-----------------|
| Variables | `#{ variable }#` | `{{ variable }}` |
| Blocks | `#% if condition %# ... #% endif %#` | `{% if %} ... {% endif %}` |
| Comments | `#| comment #|` | `{# comment #}` |

Templates are located in `templates/config/` and `templates/overrides/`, with custom filters in `templates/scripts/plugin.py`:

```python
nthhost(cidr, index)      # Get Nth host in CIDR range
age_key(key_type)         # Extract age public/private key
basename(path)            # Get filename without extension
```

## Verify Encryption

Before pushing, verify all secrets are encrypted:

```sh
# All .sops.yaml files should contain 'sops:' metadata
grep -r "sops:" kubernetes/**/*.sops.yaml bootstrap/**/*.sops.yaml
```

## Push Configuration

```sh
git add -A
git commit -m "chore: initial commit"
git push
```

!!! warning
    Using a **private repository**? Paste the public key from `github-deploy.key.pub` into your repository's deploy keys settings.
