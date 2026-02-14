# Identity & SSO

## Kanidm

[Kanidm](https://kanidm.com/) provides centralized identity management and OAuth2/OIDC single sign-on for the cluster.

### Architecture

Located in `kubernetes/apps/identity/kanidm/`:

- Deployed via the **Kaniop** Kubernetes operator
- Single Rust binary with embedded database (no external PostgreSQL needed)
- ~80 MB RAM footprint
- Manages users, groups, and OAuth2 clients declaratively via CRDs

### OAuth2 Integrations

Kanidm provides SSO for these applications:

| Application | Namespace | Authentication |
|-------------|-----------|---------------|
| DBGate | database | OAuth2/OIDC |
| Forgejo | utils | OAuth2/OIDC |
| KubeVirt Manager | kubevirt | OAuth2/OIDC |
| OpenCost | observability | OAuth2/OIDC |
| Penpot | utils | OAuth2/OIDC |

Each OAuth2 client is defined as a separate YAML file under `kubernetes/apps/identity/kanidm/app/`.

### Features

- **OAuth2/OIDC** -- Certified provider with mandatory PKCE
- **Passkeys/WebAuthn** -- Best-in-class (maintains `webauthn-rs`)
- **RADIUS** -- Built-in for WiFi WPA2-Enterprise
- **SSH key distribution** -- Cached and direct modes
- **Unix/PAM integration** -- TPM-backed credential caching
- **LDAP** -- Read-only gateway

### Adding SSO to a New Application

1. Create a `KanidmOAuth2Client` CRD in `kubernetes/apps/identity/kanidm/app/`
2. Configure the application with the OIDC provider URL and client credentials
3. Optionally add an Envoy Gateway `SecurityPolicy` for apps without native OIDC

### Envoy Gateway OIDC Integration

For apps without native OIDC support, use Envoy Gateway's SecurityPolicy:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: app-oidc
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

### kGuardian

[kGuardian](https://github.com/kguardian-dev/kguardian) provides eBPF-based security monitoring:

- **Broker** (v1.6.0) -- Message broker for security events
- **Controller** (v1.7.0) -- Core monitoring engine
- **Frontend** (v1.6.2) -- Web UI for security insights
- Uses external CloudNative-PG database
- Auto-generates NetworkPolicy and seccomp profiles from observed runtime behavior
