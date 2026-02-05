# KubeVirt Virtual Machines

This directory contains KubeVirt VirtualMachine definitions using Flux variable substitution for easy configuration.

## Adding a New VM

### 1. Copy an existing VM directory

```bash
cp -r debian-server my-new-vm
```

### 2. Update the ConfigMap

Edit `my-new-vm/app/configmap.yaml` with your VM's configuration:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-new-vm-vars
data:
  VM_NAME: my-new-vm
  VM_IP: 192.168.57.XX
  VM_MAC: "52:54:00:57:00:XX"
  VM_CPU: "1"
  VM_MEMORY: 1G
  VM_STORAGE: 30Gi
  VM_GATEWAY: 192.168.57.1
  VM_DNS: 192.168.57.1
  VM_NETWORK: network/vm-macvtap
  VM_IMAGE: "docker://quay.io/containerdisks/debian:13"
```

### 3. Update the Flux Kustomization

Edit `my-new-vm/ks.yaml`:

- Update `metadata.name` to `my-new-vm`
- Update `spec.path` to `./kubernetes/apps/kubevirt/virtualmachines/my-new-vm/app`
- Update `postBuild.substituteFrom` ConfigMap name to `my-new-vm-vars`

### 4. Register the VM

Add to `kubernetes/apps/kubevirt/kustomization.yaml`:

```yaml
resources:
  # ... existing resources ...
  - ./virtualmachines/my-new-vm/app/configmap.yaml  # Add with other ConfigMaps
  # ... existing ks.yaml resources ...
  - ./virtualmachines/my-new-vm/ks.yaml             # Add with other ks.yaml
```

## Variable Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `VM_NAME` | VM identifier (used for naming resources) | `debian-server` |
| `VM_IP` | Static IP address | `192.168.57.11` |
| `VM_MAC` | MAC address for macvtap network | `52:54:00:57:00:11` |
| `VM_CPU` | Number of CPU cores | `1` |
| `VM_MEMORY` | Memory allocation | `1G` |
| `VM_STORAGE` | Root disk size | `30Gi` |
| `VM_GATEWAY` | Network gateway | `192.168.57.1` |
| `VM_DNS` | DNS server | `192.168.57.1` |
| `VM_NETWORK` | Multus network name | `network/vm-macvtap` |
| `VM_IMAGE` | Container disk image URL | `docker://quay.io/containerdisks/debian:13` |

### Windows-specific Variables

| Variable | Description |
|----------|-------------|
| `VM_IMAGE` | Windows installation ISO container image |
| `VM_DRIVERS_IMAGE` | VirtIO drivers ISO container image |

## Available Container Disk Images

### Linux

- Debian: `docker://quay.io/containerdisks/debian:13`
- Ubuntu: `docker://quay.io/containerdisks/ubuntu:24.04`
- Fedora: `docker://quay.io/containerdisks/fedora:40`
- CentOS Stream: `docker://quay.io/containerdisks/centos-stream:9`

### Windows

Windows requires custom container images with the installation ISO and VirtIO drivers.

## Directory Structure

```
virtualmachines/
├── README.md
├── debian-server/
│   ├── app/
│   │   ├── configmap.yaml      # VM-specific variables
│   │   ├── virtualmachine.yaml # VM definition (uses ${VAR} syntax)
│   │   ├── dnsendpoint.yaml    # DNS record
│   │   └── kustomization.yaml  # App manifest list
│   └── ks.yaml                 # Flux Kustomization
└── ...
```

## Tips

- **MAC addresses**: Use the `52:54:00:57:00:XX` prefix for consistency
- **IP addresses**: Use the `192.168.57.XX` range for VM network
- **Storage class**: Default is `nfs-fast` for live migration support
- **DNS**: VMs get DNS records at `${VM_NAME}.00o.sh`

## Troubleshooting

### Check VM status
```bash
kubectl get vms -n kubevirt
kubectl get vmis -n kubevirt
```

### Check DataVolume provisioning
```bash
kubectl get dv -n kubevirt
kubectl get pvc -n kubevirt
```

### View VM console
```bash
virtctl console <vm-name> -n kubevirt
```

### Check Flux Kustomization status
```bash
flux get ks -n flux-system | grep <vm-name>
```
