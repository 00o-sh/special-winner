# Contributing

## Git Commit Conventions

This repository uses **semantic commits** with Renovate conventions:

```
<type>(<scope>): <message>
```

### Types

| Type | Usage |
|------|-------|
| `feat` | New feature |
| `fix` | Bug fix |
| `chore` | Maintenance |
| `ci` | CI/CD changes |
| `docs` | Documentation |
| `refactor` | Code refactoring |

### Scopes

| Scope | Usage |
|-------|-------|
| `container` | Docker images |
| `helm` | Helm charts |
| `github-action` | GitHub Actions |
| `kubernetes` | Kubernetes manifests |
| `observability` | Monitoring and alerting |
| `volsync` | Backup and replication |
| `github` | GitHub configuration |
| `mise` | Development tools |
| `media` | Media applications |
| `network` | Network infrastructure |
| `utils` | Utility services |

### Examples

```
fix(container): update image ghcr.io/app/name ( 1.0.0 → 1.1.0 )
feat(helm): update chart app-template ( 3.0.0 → 4.0.0 )
ci(github-action): update action/checkout ( v3 → v4 )
docs(github): update CLAUDE.md with current repository state
```

## Application Checklist

When adding a new application, follow this checklist:

- [ ] Create directory: `kubernetes/apps/<namespace>/<app-name>/app/`
- [ ] Create `helmrelease.yaml`, `ocirepository.yaml`, `kustomization.yaml`
- [ ] Create `ks.yaml` Flux Kustomization
- [ ] Update namespace `kustomization.yaml`
- [ ] Encrypt secrets with SOPS (if needed)
- [ ] Consider Kanidm SSO integration (web UI apps)
- [ ] Add to Homepage dashboard
- [ ] Add VolSync backup config (stateful apps)
- [ ] Add monitoring (ServiceMonitor/PodMonitor)
- [ ] Add Discord alerts (critical apps)
- [ ] Add NFS-scaler component (NFS-dependent apps)
- [ ] Update CLAUDE.md deployed applications list

## Security Guidelines

- **Never commit unencrypted secrets** -- Use `*.sops.yaml` files
- **Validate encryption** -- Check for `sops:` metadata
- **Follow security contexts**:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: ["ALL"] }
```

## Common Mistakes

1. Don't modify files in `talos/clusterconfig/` (generated)
2. Don't commit plaintext secrets
3. Don't skip `task configure` after template changes
4. Don't push directly to main
5. Be aware of **Helm v4** breaking changes from v3
6. Some workflows need the self-hosted runner (`special-winner-runner`)

## Bash Script Conventions

Scripts in `scripts/` use:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
export ROOT_DIR="$(git rev-parse --show-toplevel)"
```

### Logging

```bash
log debug "Debug message"
log info "Information message" "var=value"
log warn "Warning message"
log error "Error message"  # Exits with code 1
```

### Environment Checks

```bash
check_env KUBECONFIG TALOSCONFIG
check_cli kubectl flux sops
```
