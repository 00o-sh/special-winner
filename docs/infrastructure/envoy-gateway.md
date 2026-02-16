# Envoy Gateway

[Envoy Gateway](https://gateway.envoyproxy.io/) v1.6.3 provides HTTP routing and ingress using the Kubernetes Gateway API.

## Architecture

Envoy Gateway deploys Envoy Proxy instances that handle incoming traffic:

- **envoy-internal** -- Private network access (split DNS)
- **envoy-external** -- Public access via Cloudflare Tunnel

## Configuration

```
kubernetes/apps/network/envoy-gateway/
├── app/
│   ├── helmrelease.yaml      # Envoy Gateway operator
│   ├── ocirepository.yaml    # Chart source
│   ├── certificate.yaml      # TLS wildcard certificate
│   ├── envoy.yaml            # Gateway config, policies, responseOverride
│   ├── grafanadashboard.yaml # Monitoring dashboard
│   ├── podmonitor.yaml       # Prometheus metrics
│   └── kustomization.yaml
├── error-pages/
│   ├── helmrelease.yaml      # Error pages service (app-template)
│   ├── ocirepository.yaml    # Chart source
│   └── kustomization.yaml
└── ks.yaml                   # Flux Kustomizations (gateway + error-pages)
```

## Exposing Applications

### Internal Only

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "my-app.example.com"
  rules:
    - backendRefs:
        - name: my-app
          port: 80
```

### Public (via Cloudflare)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
spec:
  parentRefs:
    - name: envoy-external
      namespace: network
  hostnames:
    - "my-app.example.com"
  rules:
    - backendRefs:
        - name: my-app
          port: 80
```

## SSO Integration

Envoy Gateway supports OIDC SecurityPolicy for Kanidm SSO:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: kanidm-oidc
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: <app-route>
  oidc:
    provider:
      issuer: "https://idm.example.com/oauth2/openid/<client>"
    clientID: "<client-name>"
    clientSecret:
      name: "<secret-name>"
```

## Custom Error Pages

[Error Pages](https://github.com/tarampampam/error-pages) provides styled error responses for all routes behind both gateways. When a backend returns an error, the `BackendTrafficPolicy` `responseOverride` redirects the client to the error-pages service.

**Handled status codes:** 403, 404, 500, 502, 503, 504

The `responseOverride` in the `BackendTrafficPolicy` (in `envoy.yaml`) uses redirect rules:

```yaml
responseOverride:
  - match:
      statusCodes:
        - type: Value
          value: 404
    redirect:
      scheme: https
      hostname: error.example.com
      path:
        type: ReplaceFullPath
        replaceFullPath: /404.html
      statusCode: 302
```

This applies globally to all routes behind `envoy-internal` and `envoy-external` since the policy targets all Gateways via `targetSelectors`.

**Template:** The error-pages service uses the "hacker-terminal" template with `SHOW_DETAILS=true`.

## Monitoring

- Grafana dashboard enabled via GrafanaOperator
- PodMonitor exports metrics to Prometheus
