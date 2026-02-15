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
