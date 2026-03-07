# Rochelle Cluster Configuration

This directory will contain rochelle-specific configuration files when the
cluster hardware comes online.

## TODO

- [ ] Generate rochelle Age keypair: `age-keygen -o rochelle.key`
- [ ] Store in 1Password as "Kubernetes - rochelle - Age Key"
- [ ] Replace `ROCHELLE_AGE_PUBLIC_KEY_PLACEHOLDER` in `.sops.yaml`
- [ ] Re-encrypt shared secrets with both cluster keys
- [ ] Add rochelle-specific SOPS-encrypted secrets here
