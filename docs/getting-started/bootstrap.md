# Bootstrap

!!! warning
    Bootstrap takes **10+ minutes**. Errors like "couldn't get current server API group list" and "no matching resources found" are **normal** during this process. If interrupted with Ctrl+C, you may need to [reset the cluster](../operations/troubleshooting.md#reset-cluster) before retrying.

## Stage 1: Install Talos

```sh
task bootstrap:talos
```

Push the generated secrets:

```sh
git add -A
git commit -m "chore: add talhelper encrypted secret"
git push
```

## Stage 2: Install Core Components

This installs Cilium (CNI), CoreDNS (DNS), Flux (GitOps), and syncs the cluster to Git:

```sh
task bootstrap:apps
```

!!! note
    Spegel (peer-to-peer image sharing) automatically activates when a second node joins the cluster.

## Stage 3: Watch Deployment

```sh
kubectl get pods --all-namespaces --watch
```

## What Happens During Bootstrap

The `scripts/bootstrap-apps.sh` script runs these steps:

1. **Wait for nodes** -- Polls until nodes reach maintenance mode
2. **Apply namespaces** -- Creates all namespace resources
3. **Apply SOPS secrets** -- Decrypts and applies bootstrap secrets (deploy key, age key, cluster secrets)
4. **Apply CRDs** -- Extracts CRDs from Helmfile (`00-crds.yaml`)
5. **Sync Helm releases** -- Installs core applications from Helmfile (`01-apps.yaml`)
6. **Apply ClusterSecretStore** -- Configures 1Password integration

After bootstrap, Flux takes over and continuously reconciles the cluster state from Git.
