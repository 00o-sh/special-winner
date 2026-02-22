# Virtualization

[KubeVirt](https://kubevirt.io/) 1.7.0 enables virtual machine management within the Kubernetes cluster.

## Components

| Component | Purpose |
|-----------|---------|
| **KubeVirt** | VM lifecycle operator |
| **CDI** | Containerized Data Importer for disk provisioning |
| **KubeVirt Manager** | Web UI at `kubevirt.00o.sh` |
| **Macvtap CNI** | Direct network access for VMs |

## Feature Gates

- **LiveMigration** -- Move VMs between nodes without downtime
- **Macvtap** -- Direct network attachment
- **HotplugVolumes** -- Attach/detach volumes without restart
- **HostDevices** -- PCI device passthrough
- **GPU** -- GPU passthrough support
- **NetworkBindingPlugins** -- Advanced networking

## Current VMs

| VM | OS | CPU | RAM | Storage |
|----|----|-----|-----|---------|
| debian-desktop | Debian 13 + XFCE4 | 1 | 1Gi | 50Gi NFS |
| debian-server | Debian 13 headless | 1 | 1Gi | 50Gi NFS |
| ubuntu-server | Ubuntu | 1 | 1Gi | varies |
| windows-server | Windows Server 2022 | 2 | 2Gi | 60Gi NFS |
| freepbx-b1-k3s01 | Debian 12 + [FreePBX](freepbx.md) | 2 | 4Gi | 50Gi NFS |
| freepbx-b2-k3s01 | Debian 12 + [FreePBX](freepbx.md) | 2 | 4Gi | 50Gi NFS |
| freepbx-b3-k3s01 | Debian 12 + [FreePBX](freepbx.md) | 2 | 4Gi | 50Gi NFS |

## Storage

- VM disks use **NFS** (`nfs-fast` storageClass) with ReadWriteMany access
- Enables live migration between nodes
- CDI uses `openebs-hostpath` for scratch space during disk imports

## Networking

- VMs use **Multus** with **macvtap** for direct L2 network access
- Each VM has a dedicated MAC address
- DNS endpoints configured via external-dns

## VM Management

### CLI (virtctl)

```sh
virtctl console <vm-name>      # Access VM console
virtctl ssh <vm-name>          # SSH into VM
virtctl start <vm-name>        # Start VM
virtctl stop <vm-name>         # Stop VM
virtctl migrate <vm-name>      # Live migrate VM
virtctl restart <vm-name>      # Restart VM
```

### Task Runner

```sh
task vm:console VM=<name>
task vm:start VM=<name>
task vm:stop VM=<name>
```

### Web UI

KubeVirt Manager is accessible at `kubevirt.00o.sh` with Kanidm SSO.

## Adding a New VM

1. Create a VirtualMachine manifest in `kubernetes/apps/kubevirt/virtualmachines/`
2. Define disk source (CDI DataVolume or existing PVC)
3. Configure networking (macvtap interface with MAC address)
4. Add external-dns annotation for DNS entry
5. Add to the namespace kustomization
