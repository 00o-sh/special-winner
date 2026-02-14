# Talos Linux

[Talos Linux](https://www.talos.dev/) is an immutable, minimal OS designed specifically for Kubernetes. Version **1.12.4** is deployed.

## Configuration

Talos configuration is managed through [talhelper](https://budimanjojo.github.io/talhelper/latest/) and Jinja2 templates.

### File Locations

| Path | Purpose |
|------|---------|
| `templates/config/talos/talconfig.yaml.j2` | Main Talos config template |
| `talos/patches/global/` | Patches applied to all nodes |
| `talos/patches/controller/` | Controller-specific patches |
| `talos/patches/worker/` | Worker-specific patches |
| `talos/patches/vm-node/` | KubeVirt VM node patches |
| `talos/patches/${hostname}/` | Per-node patches |
| `talos/clusterconfig/` | Generated configs (gitignored) |

### Patch System

Talos uses a layered patch system. Patches are applied in order:

1. Global patches (all nodes)
2. Role-specific patches (controller or worker)
3. VM-node patches (KubeVirt nodes)
4. Per-hostname patches

## Common Operations

### Generate Config

```sh
task talos:generate-config
```

### Apply Config to a Node

```sh
task talos:apply-node IP=10.10.10.10 MODE=auto
```

Mode options: `auto`, `no-reboot`, `reboot`, `staged`

### Upgrade Talos Version

```sh
task talos:upgrade-node IP=10.10.10.10
```

!!! tip
    Update `talosVersion` in `talenv.yaml` before upgrading.

### Upgrade Kubernetes Version

```sh
task talos:upgrade-k8s
```

### Reset Cluster

!!! danger
    This destroys the entire cluster. Repeated resets may trigger rate limits from DockerHub or Let's Encrypt.

```sh
task talos:reset
```

## Adding a New Node

1. Boot the new node with Talos in maintenance mode
2. Get disk and MAC address info:

    ```sh
    talosctl get disks -n <ip> --insecure
    talosctl get links -n <ip> --insecure
    ```

3. Add the node to `talconfig.yaml`
4. Generate and apply:

    ```sh
    task talos:generate-config
    task talos:apply-node IP=<new-ip>
    ```

The node joins automatically and begins accepting workloads.

## Debugging

```sh
# Check cluster membership
talosctl get members --nodes <ip> --insecure

# View node logs
talosctl logs --nodes <ip> --insecure

# Check node services
talosctl services --nodes <ip>
```
