# LibreSpeed

[LibreSpeed](https://librespeed.org/) is a self-hosted speed test deployed with multiple test paths to isolate network bottlenecks at each layer of the stack.

- Located in `kubernetes/apps/default/librespeed/`
- Image: `ghcr.io/librespeed/speedtest:5.5.1`
- Namespace: `default`
- Frontend: `speed.${SECRET_DOMAIN}`

## Architecture

LibreSpeed runs as 5 separate controllers (pods), each serving a different network path:

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

### Controllers

| Controller | Mode | Gateway | TLS | Description |
|-----------|------|---------|-----|-------------|
| `speed-cf` | backend | envoy-external | Cloudflare + Envoy | Full Cloudflare proxy path |
| `speed-portfwd` | backend | envoy-external | Envoy only | Port forwarded, CF proxy disabled |
| `speed-direct` | backend | envoy-internal | Envoy | LAN only, through Envoy |
| `speed-lan` | backend | Cilium LB (10.0.6.16) | Apache mod_ssl | LAN only, no proxy |
| `speed-frontend` | frontend | envoy-external | Cloudflare + Envoy | Server picker UI |

All backend controllers run `ghcr.io/librespeed/speedtest:5.5.1` in `MODE=backend`. The frontend runs in `MODE=frontend` with a `servers.json` ConfigMap listing all backends.

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

## Hostnames

| Hostname | Purpose |
|----------|---------|
| `speed.${SECRET_DOMAIN}` | Frontend UI (server picker) |
| `speed-cf.${SECRET_DOMAIN}` | Backend via Cloudflare |
| `speed-portfwd.${SECRET_DOMAIN}` | Backend via port forward |
| `speed-direct.${SECRET_DOMAIN}` | Backend via Envoy internal |
| `speed-lan.${SECRET_DOMAIN}` | Backend via Cilium LB (no Envoy) |

## Envoy Performance Tuning

A route-specific `BackendTrafficPolicy` is applied to the speed test backend routes (`speed-cf`, `speed-direct`, `speed-portfwd`) that overrides the global gateway policy. This allows aggressive throughput settings without affecting other applications.

### Per-Route BackendTrafficPolicy

| Setting | Global Policy | Speed Test Policy | Why |
|---------|--------------|-------------------|-----|
| Compression | Brotli + Gzip | **Disabled** | Speed test data is random; compression wastes CPU for 0% savings |
| Response Override | Error page redirects | **Disabled** | Skip error page matching on every response |
| Backend Buffer | 8Mi | **16Mi** | More buffer for high-throughput data transfers |
| Circuit Breakers | 1024 (default) | **4096** | Remove connection/request concurrency limits |
| Backend Protocol | Client protocol | **HTTP/1.1** | Avoids HTTP/2 framing overhead to backend pods |

!!! info "How per-route policies work"
    When a `BackendTrafficPolicy` targets an `HTTPRoute`, it overrides the gateway-level policy for that route only. Other routes continue using the global policy with compression, error pages, etc.

### Global ClientTrafficPolicy

These settings apply to all traffic through the same gateways (cannot be scoped per-route):

| Setting | Value | Notes |
|---------|-------|-------|
| HTTP/2 Stream Window | 512Ki | 8x default; limits per-stream in-flight data |
| HTTP/2 Connection Window | 8Mi | Shared across all streams on a connection |
| Client Buffer | 4Mi | Client-side receive buffer |
| HTTP/3 | Enabled | QUIC when supported by client |

!!! warning "ClientTrafficPolicy limitation"
    `ClientTrafficPolicy` can only target `Gateway` resources, not individual `HTTPRoute` resources. The most granular targeting is per-listener via `sectionName`. This means client-side tuning (HTTP/2 windows, HTTP/3) affects all routes on that listener.

### If Envoy Still Limits Throughput

The LAN Direct test bypasses Envoy entirely. If you see a large gap between LAN Direct and Direct (Envoy), consider increasing the global HTTP/2 windows in `kubernetes/apps/network/envoy-gateway/app/envoy.yaml`:

```yaml
# ClientTrafficPolicy
http2:
  initialStreamWindowSize: 2Mi      # currently 512Ki
  initialConnectionWindowSize: 16Mi  # currently 8Mi
```

!!! warning
    Increasing these values globally affects all services. Larger windows use more memory per connection across all Envoy pods.

## LAN Direct TLS Setup

The LAN Direct server terminates TLS at the pod level (no Envoy) using a Let's Encrypt certificate provisioned by cert-manager:

- **Certificate**: `speed-lan-tls` (issued for `speed-lan.${SECRET_DOMAIN}`)
- **Issuer**: `letsencrypt-production` ClusterIssuer (DNS-01 via Cloudflare)
- **Algorithm**: ECDSA
- **Duration**: 160 hours
- **Flux dependency**: `cert-manager` → `librespeed-cert` (waits for cert readiness) → `librespeed`
- **Apache**: `mod_ssl` enabled via command override, SSL VirtualHost on port 8443
- **Service**: Cilium LoadBalancer maps `443 → 8443`

## Adding External Speed Test Servers

To add external servers (e.g., a LibreSpeed instance on a VPS), add entries to the `servers.json` ConfigMap in `helmrelease.yaml`:

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

When accessed from the internet, only **Cloudflare** and **Port Forwarded** servers are reachable. **Direct (Envoy)** and **LAN Direct** resolve to internal IPs and will fail the pre-test ping. LibreSpeed shows them as unavailable -- this is expected.

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

## Dependencies

- **cert-manager**: Provides the `speed-lan-tls` certificate for the LAN Direct path
- **Envoy Gateway**: Routes for Cloudflare, Port Forwarded, and Direct paths
- **Cilium**: LoadBalancer service for LAN Direct path (IP: 10.0.6.16)
- **External DNS**: Automatic DNS record creation for all hostnames

## Resources

Each controller runs with:

```yaml
requests:
  cpu: 10m
  memory: 64Mi
limits:
  memory: 256Mi
```

5 controllers total = 50m CPU request, 320Mi memory request, 1280Mi memory limit.
