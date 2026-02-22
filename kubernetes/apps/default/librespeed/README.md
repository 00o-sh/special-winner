# LibreSpeed - Multi-Path Speed Test

Self-hosted speed test with multiple test paths to isolate network bottlenecks.

## Architecture

```
                                    ┌──────────────────────────────┐
                                    │  speed.${SECRET_DOMAIN}      │
                                    │  Frontend (server picker UI) │
                                    └──────────────┬───────────────┘
                                                   │
                    ┌──────────────┬───────────────┼───────────────┬──────────────┐
                    ▼              ▼               ▼               ▼              │
              ┌───────────┐ ┌───────────┐  ┌────────────┐  ┌────────────┐        │
              │ Cloudflare│ │Port Fwd'd │  │Direct Envoy│  │ LAN Direct │        │
              │ speed-cf  │ │speed-prtfw│  │speed-direct│  │ speed-lan  │        │
              └─────┬─────┘ └─────┬─────┘  └─────┬──────┘  └─────┬──────┘        │
                    │             │               │               │              │
  TLS by:     Cloudflare+    Envoy Ext      Envoy Int       Apache (pod)    Envoy Ext
              Envoy Ext                                                     (frontend)
                    │             │               │               │
  Path:       CF CDN →       Router →        Envoy Int →    Cilium LB →
              Router →       Envoy Ext →     Pod            Pod (8443)
              Envoy Ext →    Pod
              Pod
```

## Test Paths

| Server | Route | TLS Terminated By | Reachable From | Measures |
|--------|-------|-------------------|----------------|----------|
| **Cloudflare** | `envoy-external` (CF proxied) | Cloudflare + Envoy | Internet + LAN | Full CF proxy overhead |
| **Port Forwarded** | `envoy-external` (CF proxy off) | Envoy | Internet + LAN | Raw internet + Envoy overhead |
| **Direct (Envoy)** | `envoy-internal` | Envoy | LAN only | Envoy proxy overhead in isolation |
| **LAN Direct** | Cilium LoadBalancer (10.0.6.16) | Apache mod_ssl (in-pod) | LAN only | Raw network baseline, no proxy |

### Interpreting Results

- **LAN Direct vs Direct (Envoy)**: Difference = Envoy proxy overhead
- **Direct (Envoy) vs Port Forwarded**: Difference = NAT/routing overhead
- **Port Forwarded vs Cloudflare**: Difference = Cloudflare CDN overhead
- **LAN Direct**: Your maximum achievable throughput (hardware baseline)

## Envoy Performance Tuning

A route-specific `BackendTrafficPolicy` is applied to the speed test backend routes
(`speed-cf`, `speed-direct`, `speed-portfwd`) that overrides the global policy:

| Setting | Global Policy | Speed Test Policy | Why |
|---------|--------------|-------------------|-----|
| Compression | Brotli + Gzip | **Disabled** | Speed test data is random; compression wastes CPU for 0% savings |
| Response Override | Error page redirects | **Disabled** | Skip error page matching on every response |
| Backend Buffer | 8Mi | **16Mi** | More buffer for high-throughput data transfers |
| Circuit Breakers | 1024 (default) | **4096** | Remove connection/request concurrency limits |
| Preconnect | Disabled | **1.5x ratio** | Proactively establish backend connections |
| Backend Protocol | Client protocol | **HTTP/1.1** | Avoids HTTP/2 framing overhead to backend pods |

The global `ClientTrafficPolicy` still applies (HTTP/2 windows, HTTP/3, TLS config).
These settings affect all traffic through the same gateways:

| Setting | Value | Notes |
|---------|-------|-------|
| HTTP/2 Stream Window | 512Ki | 8x default; limits per-stream in-flight data |
| HTTP/2 Connection Window | 8Mi | Shared across all streams on a connection |
| Client Buffer | 4Mi | Client-side receive buffer |
| HTTP/3 | Enabled | QUIC when supported by client |

### If Envoy Still Limits Throughput

The LAN Direct test bypasses Envoy entirely. If you see a large gap between LAN Direct
and Direct (Envoy), consider increasing the global HTTP/2 windows in
`kubernetes/apps/network/envoy-gateway/app/envoy.yaml`:

```yaml
# ClientTrafficPolicy
http2:
  initialStreamWindowSize: 2Mi    # currently 512Ki
  initialConnectionWindowSize: 16Mi  # currently 8Mi
```

> **Warning**: Increasing these values globally affects all services. Larger windows use
> more memory per connection across all Envoy pods.

## Adding External Speed Test Servers

To add external servers (e.g., a LibreSpeed instance on a VPS), add entries to the
`servers.json` ConfigMap in `helmrelease.yaml`:

```json
{"name": "VPS (NYC)", "server": "https://speedtest.example.com/", "dlURL": "garbage.php", "ulURL": "empty.php", "pingURL": "empty.php", "getIpURL": "getIP.php"}
```

### Requirements for External Servers

- Must run LibreSpeed in `backend` or `standalone` mode
- Must be HTTPS (mixed content blocked from HTTPS frontend)
- Must allow CORS from `speed.${SECRET_DOMAIN}` (or use `*`)
- For `MODE=backend`: endpoints are at root (`/garbage.php`)
- For `MODE=standalone`: endpoints are under `/backend/garbage.php`

### External Accessibility

When accessed from the internet, only **Cloudflare** and **Port Forwarded** servers are
reachable. **Direct (Envoy)** and **LAN Direct** resolve to internal IPs and will fail
the pre-test ping. LibreSpeed shows them as unavailable — this is expected.

To provide useful tests for external users, deploy LibreSpeed backend instances at:
- A VPS or cloud VM (measures ISP → datacenter path)
- A different geographic location (measures long-haul latency)
- Behind a different CDN (compares CDN performance)

## LAN Direct TLS Setup

The LAN Direct server terminates TLS at the pod level (no Envoy) using a Let's Encrypt
certificate provisioned by cert-manager:

- **Certificate**: `speed-lan-tls` (issued for `speed-lan.${SECRET_DOMAIN}`)
- **Flux dependency**: `cert-manager → librespeed-cert (waits for cert) → librespeed`
- **Apache**: `mod_ssl` enabled via command override, SSL VirtualHost on port 8443
- **Service**: Cilium LoadBalancer maps `443 → 8443`

## File Structure

```
librespeed/
├── app/
│   ├── backendtrafficpolicy.yaml  # Per-route Envoy tuning (no compression)
│   ├── helmrelease.yaml           # All controllers, services, routes, configs
│   ├── kustomization.yaml
│   └── ocirepository.yaml
├── cert/
│   ├── certificate.yaml           # cert-manager Certificate for LAN TLS
│   └── kustomization.yaml
├── ks.yaml                        # Flux Kustomizations (cert → app dependency)
└── README.md
```

## Hostnames

| Hostname | Purpose |
|----------|---------|
| `speed.${SECRET_DOMAIN}` | Frontend UI (server picker) |
| `speed-cf.${SECRET_DOMAIN}` | Backend via Cloudflare |
| `speed-portfwd.${SECRET_DOMAIN}` | Backend via port forward |
| `speed-direct.${SECRET_DOMAIN}` | Backend via Envoy internal |
| `speed-lan.${SECRET_DOMAIN}` | Backend via Cilium LB (no Envoy) |
