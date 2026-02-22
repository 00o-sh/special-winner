# Operations

Guides for managing the cluster day-to-day.

## Quick Reference

| Task | Command |
|------|---------|
| Force Flux sync | `task reconcile` |
| List all tasks | `task --list` |
| Generate Talos config | `task talos:generate-config` |
| Apply config to node | `task talos:apply-node IP=<ip> MODE=auto` |
| Upgrade Talos | `task talos:upgrade-node IP=<ip>` |
| Upgrade Kubernetes | `task talos:upgrade-k8s` |
| Reset cluster | `task talos:reset` |
| Failover workloads | `task failover CLUSTER=<name>` |
| Validate K8s manifests | `task template:validate-kubernetes-config` |
| VM console | `task vm:console VM=<name>` |
| VM start/stop | `task vm:start VM=<name>` / `task vm:stop VM=<name>` |

!!! tip
    All tasks accept a `CLUSTER` parameter (default: `3226`).

## Pages

- [Day-2 Operations](day2.md) -- Routine maintenance and upgrades
- [Backup & Recovery](backup-recovery.md) -- VolSync, Kopia, and disaster recovery
- [VM Management](vm-management.md) -- KubeVirt virtual machine operations
- [Troubleshooting](troubleshooting.md) -- Debugging common issues
