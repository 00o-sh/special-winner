# Troubleshooting

## Flux Issues

### Resources Not Syncing

```sh
# Check Flux health
flux check

# Check for failed reconciliations
flux get ks -A --status-selector ready=false
flux get hr -A --status-selector ready=false

# View Flux logs
flux logs --all-namespaces

# Force sync
task reconcile
```

### HelmRelease Stuck

```sh
# Suspend and resume
flux suspend hr <name> -n <namespace>
flux resume hr <name> -n <namespace>

# Force reconciliation
flux reconcile hr <name> -n <namespace> --force
```

## Template Issues

### Templates Not Rendering

```sh
task template:validate-schemas    # Check cluster.yaml & nodes.yaml
task template:render-configs      # Force re-render
```

## Secret Issues

### Secrets Not Decrypting

```sh
# Verify age key exists
test -f age.key && echo "Key exists" || echo "Missing key"

# Verify SOPS can decrypt
sops --decrypt bootstrap/sops-age.sops.yaml

# Check SOPS_AGE_KEY_FILE is set
echo $SOPS_AGE_KEY_FILE
```

### Verifying Encryption

```sh
# All .sops.yaml files should contain 'sops:' metadata
grep -l "sops:" kubernetes/**/*.sops.yaml
```

## Node Issues

### Nodes Not Joining

```sh
talosctl get members --nodes <ip> --insecure
talosctl logs --nodes <ip> --insecure
```

### Node Health

```sh
kubectl get nodes -o wide
kubectl describe node <node-name>
```

## Pod Issues

### General Debugging

```sh
# List pods in namespace
kubectl -n <namespace> get pods -o wide

# Check pod logs
kubectl -n <namespace> logs <pod-name> -f

# Describe pod for events
kubectl -n <namespace> describe pod <pod-name>

# Check namespace events
kubectl -n <namespace> get events --sort-by='.metadata.creationTimestamp'
```

### CrashLoopBackOff

1. Check logs: `kubectl -n <ns> logs <pod> --previous`
2. Check resource limits: `kubectl -n <ns> describe pod <pod>`
3. Check if NFS-dependent -- add NFS-scaler component if so
4. Check if secret is missing: `kubectl -n <ns> get secrets`

### Pending Pods

1. Check events: `kubectl -n <ns> describe pod <pod>`
2. Check node resources: `kubectl top nodes`
3. Check PVC binding: `kubectl -n <ns> get pvc`
4. Check node affinity/taints

## Network Issues

### Cilium

```sh
cilium status
cilium connectivity test
```

### DNS

```sh
# Test cluster DNS
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default

# Test external DNS resolution
dig @<k8s-gateway-ip> <app>.<domain>
```

## Storage Issues

### NFS Unavailable

If NFS is down, pods using NFS volumes will crash-loop. The NFS-scaler component handles this automatically for apps that include it.

Check NFS availability:

```sh
kubectl -n observability get prometheusrule -l app=blackbox-exporter
```

### PVC Issues

```sh
kubectl get pvc -A
kubectl describe pvc <name> -n <namespace>
```

## VM Issues

### VM Not Starting

```sh
# Check VirtualMachine status
kubectl -n kubevirt get vm <vm-name>
kubectl -n kubevirt describe vm <vm-name>

# Check VirtualMachineInstance (the running instance)
kubectl -n kubevirt get vmi <vm-name>

# Check CDI DataVolume import status (for new VMs)
kubectl -n kubevirt get dv <vm-name>-disk
kubectl -n kubevirt describe dv <vm-name>-disk
```

### VM Console Not Connecting

```sh
# Ensure virtctl is installed
virtctl version

# Try direct console access
virtctl console <vm-name> -n kubevirt

# Check VMI is in Running phase
kubectl -n kubevirt get vmi <vm-name> -o jsonpath='{.status.phase}'
```

### VM Live Migration Fails

Requirements for live migration:

1. Storage must be ReadWriteMany (NFS `nfs-fast` class)
2. LiveMigration feature gate must be enabled (default)
3. Sufficient resources on the target node
4. No hostPath mounts

```sh
# Check migration status
kubectl -n kubevirt get vmim
kubectl -n kubevirt describe vmim <migration-name>
```

## Database Issues

### PostgreSQL Cluster Unhealthy

```sh
# Check cluster status
kubectl -n database get cluster postgres

# Check individual pod status
kubectl -n database get pods -l cnpg.io/cluster=postgres

# View PostgreSQL logs
kubectl -n database logs -l cnpg.io/cluster=postgres --tail=50

# Check replication status
kubectl -n database exec -it postgres-1 -- psql -U postgres -c 'SELECT * FROM pg_stat_replication;'
```

### PostgreSQL Connection Issues

```sh
# Verify the service exists
kubectl -n database get svc postgres-rw

# Test connectivity from a debug pod
kubectl run -it --rm pg-debug --image=postgres:17 -- \
  psql -h postgres-rw.database.svc.cluster.local -U postgres
```

### PostgreSQL Backup Failures

```sh
# Check scheduled backup status
kubectl -n database get scheduledbackups
kubectl -n database get backups --sort-by='.metadata.creationTimestamp'

# Check WAL archiving
kubectl -n database get cluster postgres -o jsonpath='{.status.firstRecoverabilityPoint}'
```

## Certificate Issues

### Certificate Not Ready

```sh
# Check certificate status
kubectl -n network get certificates
kubectl -n network describe certificate <cert-name>

# Check certificate requests
kubectl get certificaterequests -A

# Check cert-manager logs
kubectl -n cert-manager logs -l app.kubernetes.io/name=cert-manager --tail=50
```

### Common Certificate Problems

1. **DNS challenge failing**: Check Cloudflare API token permissions
2. **Rate limited by Let's Encrypt**: Wait and retry (check `kubectl describe certificate`)
3. **Secret not found**: Verify the certificate secret name matches the TLS secret reference in your Gateway

## Reset Cluster

!!! danger
    This destroys everything. Use as last resort.

```sh
task talos:reset
```

After reset, re-bootstrap:

```sh
task bootstrap:talos
task bootstrap:apps
```
