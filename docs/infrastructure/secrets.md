# Secrets Management

## Overview

Secrets are managed through two complementary systems:

1. **SOPS + Age** -- Encrypts secrets stored in Git
2. **External Secrets Operator** -- Pulls secrets from 1Password at runtime

## SOPS + Age

[SOPS](https://github.com/getsops/sops) encrypts YAML files using [Age](https://github.com/FiloSottile/age) keys.

### Encryption Rules (`.sops.yaml`)

| Path Pattern | Encryption Scope |
|-------------|-----------------|
| `talos/.*\.sops\.ya?ml` | Full file encryption |
| `(bootstrap\|kubernetes)/.*\.sops\.ya?ml` | Only `data` and `stringData` fields |

### Encrypting a Secret

```sh
sops --encrypt --in-place kubernetes/apps/<namespace>/<app>/app/secret.sops.yaml
```

### Decrypting a Secret

```sh
sops --decrypt kubernetes/apps/<namespace>/<app>/app/secret.sops.yaml
```

### Key Management

- Age public key: defined in `.sops.yaml`
- Age private key: stored in `age.key` (gitignored)
- Environment variable: `SOPS_AGE_KEY_FILE` points to `age.key`

## External Secrets Operator

[External Secrets Operator](https://external-secrets.io/) v2.0.0 syncs secrets from external providers into Kubernetes.

### 1Password Integration

A `ClusterSecretStore` connects to 1Password:

```
kubernetes/apps/external-secrets/
├── external-secrets/    # Operator deployment
├── onepassword/         # ClusterSecretStore config
└── discord-webhook/     # Discord integration
```

Applications reference secrets via `ExternalSecret` resources that pull values from 1Password vaults.

### Creating an ExternalSecret

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-secret
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: app-secret
  data:
    - secretKey: password
      remoteRef:
        key: my-1password-item
        property: password
```

## Best Practices

!!! danger "Never commit unencrypted secrets"
    All sensitive data must be in `*.sops.yaml` files. Verify encryption by checking for `sops:` metadata in the file.

- Use `ExternalSecret` for runtime secrets from 1Password
- Use `SOPS` for secrets that must exist in Git (bootstrap, cluster config)
- Always validate that `*.sops.yaml` files are encrypted before pushing
- Renovate is configured to ignore `**/*.sops.*` files
