# VM Management

## Overview

Virtual machines are managed by [KubeVirt](https://kubevirt.io/) 1.7.0 with VM definitions stored in Git at `kubernetes/apps/kubevirt/virtualmachines/`.

## CLI Operations

### Using virtctl

```sh
# Access VM console
virtctl console <vm-name>

# SSH into VM
virtctl ssh <vm-name>

# Start/stop
virtctl start <vm-name>
virtctl stop <vm-name>

# Restart
virtctl restart <vm-name>

# Live migrate to another node
virtctl migrate <vm-name>

# Pause/unpause
virtctl pause vm <vm-name>
virtctl unpause vm <vm-name>
```

### Using Task Runner

```sh
task vm:console VM=<name>
task vm:start VM=<name>
task vm:stop VM=<name>
```

## Web UI

KubeVirt Manager is available at `kubevirt.00o.sh` with Kanidm SSO authentication.

## Creating a New VM

### 1. Create the Manifest

Create a directory under `kubernetes/apps/kubevirt/virtualmachines/<vm-name>/`:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: my-vm
spec:
  running: true
  template:
    spec:
      domain:
        cpu:
          cores: 2
        memory:
          guest: 2Gi
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              macvtap: {}
              macAddress: "XX:XX:XX:XX:XX:XX"
      networks:
        - name: default
          multus:
            networkName: macvtap-net
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: my-vm-disk
```

### 2. Create Storage

Use CDI DataVolume to import a disk image:

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: my-vm-disk
spec:
  source:
    http:
      url: "https://cloud-images.ubuntu.com/..."
  storage:
    accessModes:
      - ReadWriteMany
    storageClassName: nfs-fast
    resources:
      requests:
        storage: 50Gi
```

### 3. Configure Networking

Each VM gets a macvtap interface with a dedicated MAC address for direct L2 network access. Add an external-dns annotation for DNS.

### 4. Add to Kustomization

Reference the new VM in `kubernetes/apps/kubevirt/virtualmachines/kustomization.yaml`.

## Live Migration

VMs using NFS storage (`nfs-fast`) support live migration:

```sh
virtctl migrate <vm-name>
```

Requirements:

- ReadWriteMany storage (NFS)
- LiveMigration feature gate enabled (default)
- Sufficient resources on target node

## FreePBX VMs

Three FreePBX telephony instances are deployed:

- `freepbx-b1-k3s01`
- `freepbx-b2-k3s01`
- `freepbx-b3-k3s01`

Each has dedicated SOPS-encrypted secrets.
