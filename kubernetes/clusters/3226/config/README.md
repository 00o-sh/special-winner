# 3226 Cluster Configuration

This directory contains 3226-specific configuration.

The cluster-local variables (ConfigMap `cluster-local-vars`) are embedded directly
in `kubernetes/clusters/3226/flux/ks.yaml` to ensure they are deployed alongside
the Flux bootstrap.

## Age Key

- Public key: `age17a9gk8fq0rz9utn3jzhtc2nqvypk996cj5eamuw75j73uphvsursv37973`
- Stored in 1Password as "Kubernetes - 3226 - Age Key"
