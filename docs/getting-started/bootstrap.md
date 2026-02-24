# Bootstrap

!!! warning
    Bootstrap takes **10+ minutes**. Errors like "couldn't get current server API group list" and "no matching resources found" are **normal** during this process. If interrupted with Ctrl+C, you may need to [reset the cluster](../operations/troubleshooting.md#reset-cluster) before retrying.

## Stage 1: Install Talos

```sh
task bootstrap:talos CLUSTER=3226
```

!!! tip
    All tasks accept a `CLUSTER` parameter. The default is `3226` if omitted.

Push the generated secrets:

```sh
git add -A
git commit -m "chore: add talhelper encrypted secret"
git push
```

## Stage 2: Install Core Components

This installs Cilium (CNI), CoreDNS (DNS), Flux (GitOps), and syncs the cluster to Git:

```sh
task bootstrap:apps CLUSTER=3226
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

## Bootstrapping Additional Clusters

The repository supports managing multiple clusters. To add a new cluster:

1. **Initialize** the cluster config:

    ```sh
    task init CLUSTER=<new-name>
    ```

2. **Edit** `clusters/<new-name>/cluster.yaml` and `clusters/<new-name>/nodes.yaml`

3. **Create a Flux entry point** (new clusters start as standby):

    ```sh
    cp kubernetes/flux/3226/ks.yaml kubernetes/flux/<new-name>/ks.yaml
    ```

    Set `SUSPEND_DEFAULT: "true"` in the new `ks.yaml` so workloads start suspended.

4. **Render and validate**:

    ```sh
    task configure CLUSTER=<new-name>
    ```

5. **Bootstrap**:

    ```sh
    task bootstrap:talos CLUSTER=<new-name>
    task bootstrap:apps CLUSTER=<new-name>
    ```

See [Failover](../operations/day2.md#cluster-failover) for activating the new cluster.
