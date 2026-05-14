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
| Validate K8s manifests | `task template:validate-kubernetes-config` |
| VM console | `task vm:console VM=<name>` |
| VM start/stop | `task vm:start VM=<name>` / `task vm:stop VM=<name>` |
| Mass VolSync restore | `./scripts/volsync-restore-all.sh` |
| Generate GitHub labels | `./scripts/generate-labels.sh` |

## Pages

- [Day-2 Operations](day2.md) -- Routine maintenance and upgrades
- [Backup & Recovery](backup-recovery.md) -- VolSync, Kopia, and disaster recovery
- [Node Loss Recovery](node-loss-recovery.md) -- Recovering from a permanently lost node (orphaned PVCs, dangling instances)
- [VM Management](vm-management.md) -- KubeVirt virtual machine operations
- [Troubleshooting](troubleshooting.md) -- Debugging common issues
