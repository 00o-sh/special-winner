# Cilium Networking

[Cilium](https://cilium.io/) 1.19.0 provides eBPF-based container networking, fully replacing kube-proxy.

## Key Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| **kubeProxyReplacement** | `true` | Replaces kube-proxy entirely with eBPF |
| **routingMode** | `native` | Direct routing without tunneling overhead |
| **loadBalancer.algorithm** | `maglev` | Consistent hashing for load distribution |
| **loadBalancer.mode** | `dsr` | Direct Server Return (reduces return path latency) |
| **ipam.mode** | `kubernetes` | Uses Kubernetes for IP address management |
| **l2announcements** | enabled | Announces LoadBalancer IPs via L2 discovery |
| **cni.exclusive** | `false` | Allows Multus CNI for multi-network support |
| **devices** | `bond+` | Binds to bonded network interfaces |

## Architecture

```
kubernetes/apps/kube-system/cilium/
├── app/
│   ├── helmrelease.yaml      # Cilium agent + operator config
│   ├── ocirepository.yaml    # Chart source
│   └── kustomization.yaml
└── ks.yaml
```

## Load Balancing

Cilium provides L2 load balancing for `LoadBalancer` services:

- **IP Pool**: `10.0.6.0/24` (`CiliumLoadBalancerIPPool`)
- **Announcement**: L2 ARP on bonded interfaces (`CiliumL2AnnouncementPolicy`)
- **Algorithm**: Maglev consistent hashing
- **Mode**: DSR (Direct Server Return) for reduced latency

Services with `type: LoadBalancer` automatically get an IP from the pool. Examples:

| Service | LoadBalancer IP |
|---------|----------------|
| Plex | `10.0.6.14` |
| SMTP Relay | `10.0.6.15` |

## Monitoring

Cilium exports Prometheus metrics with two pre-configured Grafana dashboards:

- **cilium-agent** (Grafana ID: 16611) — Agent metrics, datapath performance
- **cilium-operator** (Grafana ID: 16612) — Operator health and status

Both Prometheus ServiceMonitor and operator metrics are enabled.

## Hubble (Observability)

If enabled, Hubble provides network flow visibility:

```sh
hubble status
hubble observe --follow
hubble observe --namespace <namespace>  # Filter by namespace
```

## Checking Status

```sh
# Overall Cilium health
cilium status

# Full connectivity test suite
cilium connectivity test

# Check BPF maps and routing
cilium bpf lb list          # LoadBalancer entries
cilium bpf endpoint list    # Endpoint mappings
```

## Troubleshooting

### Pods Can't Reach Services

```sh
# Check Cilium agent status on the node
cilium status
kubectl -n kube-system logs -l k8s-app=cilium --tail=50

# Verify endpoints are programmed
cilium endpoint list
```

### LoadBalancer IP Not Responding

```sh
# Verify the IP pool has available addresses
kubectl get ciliumloadbalancerippool -o yaml

# Check L2 announcement policy
kubectl get ciliuml2announcementpolicy -o yaml

# Verify the service has an external IP assigned
kubectl get svc -A | grep LoadBalancer
```

### Connectivity Between Nodes

```sh
# Run the built-in connectivity test
cilium connectivity test

# Check node-to-node routing
cilium bpf tunnel list
```
