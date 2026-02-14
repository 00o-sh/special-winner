# Template System

The cluster uses [makejinja](https://github.com/mirkolenz/makejinja) for configuration templating.

## Configuration

Defined in `makejinja.toml`:

```toml
[makejinja]
inputs = ["./templates/overrides","./templates/config"]
output = "./"
exclude_patterns = ["*.partial.yaml.j2"]
data = ["./cluster.yaml", "./nodes.yaml"]
import_paths = ["./templates/scripts"]
jinja_suffix = ".j2"
force = true
undefined = "chainable"
```

## Custom Delimiters

To avoid conflicts with YAML and Helm templating:

| Element | Syntax | Standard Jinja2 |
|---------|--------|-----------------|
| Variables | `#{ variable }#` | `{{ variable }}` |
| Blocks | `#% if condition %# ... #% endif %#` | `{% if %} ... {% endif %}` |
| Comments | `#| comment #|` | `{# comment #}` |

## Custom Filters

Located in `templates/scripts/plugin.py`:

| Filter | Usage | Example |
|--------|-------|---------|
| `nthhost` | Get Nth host in CIDR | `#{ "10.0.0.0/24" \| nthhost(1) }#` → `10.0.0.1` |
| `age_key` | Extract age key | `#{ "public" \| age_key }#` |
| `basename` | Filename without ext | `#{ "path/file.txt" \| basename }#` → `file` |

## Data Sources

Templates read from two configuration files (generated via `task init`, gitignored):

- **`cluster.yaml`** -- Cluster-wide settings
- **`nodes.yaml`** -- Node definitions

## Directory Structure

```
templates/
├── config/           # Main configuration templates
│   └── talos/       # Talos Linux config templates
├── overrides/       # Output file overrides
└── scripts/         # Custom Jinja2 filters
    └── plugin.py    # nthhost, age_key, basename
```

## Workflow

```sh
# Generate configs from samples
task init

# Edit cluster.yaml and nodes.yaml

# Render templates and validate
task configure

# Validate specific configs
task template:validate-kubernetes-config
task template:validate-talos-config

# Clean up after bootstrap
task template:tidy
```

!!! warning
    Never modify files in `talos/clusterconfig/` directly -- they are generated from templates. Edit the source templates instead.
