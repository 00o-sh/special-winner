# SSO Provider Research for Kubernetes Homelab (GitOps-Friendly)

> Researched 2026-02-07. Stack: Flux CD, Envoy Gateway, CloudNative-PG, Talos Linux, onedr0p/cluster-template.

## Recommendation: Authelia

Authelia is the best fit for this cluster due to native Envoy Gateway support, fully declarative YAML configuration (GitOps-native), minimal resource usage (~30 MB RAM), and strong adoption in the cluster-template community.

## Comparison Matrix

| Feature | Authelia | Authentik | Keycloak | Zitadel | Kanidm |
|---|---|---|---|---|---|
| RAM (baseline) | ~30 MB | ~600 MB-1 GB | ~400+ MB | ~512 MB-1 GB | ~80 MB |
| OCI Helm Chart | No (traditional repo) | Yes (ghcr.io) | Yes (Bitnami) | No (traditional) | Yes (Kaniop) |
| Envoy Gateway ext-auth | Native (first-class) | Supported (minor bug) | Via oauth2-proxy | Via oauth2-proxy | Via oauth2-proxy or native OIDC SecurityPolicy |
| Forward Auth | Native (core feature) | Native (proxy outpost) | Via oauth2-proxy | Via oauth2-proxy | Via oauth2-proxy |
| GitOps Config | Excellent (YAML) | Mixed (GUI + API) | Partial (config-cli) | API/Terraform | Kaniop CRDs + CLI bootstrap |
| PostgreSQL | Optional | Required | Required | Required | Not needed (embedded DB) |
| OIDC Provider | Yes (certified) | Yes | Yes | Yes | Yes (PKCE mandatory) |
| SAML | No | Yes | Yes | Via brokering | No |
| LDAP Server | No (pairs with LLDAP) | Yes (built-in) | Yes (federation) | No | Read-only gateway |
| RADIUS | No | No | No | No | Built-in (FreeRADIUS wrapper) |
| SSH Key Distribution | No | No | No | No | Built-in (cached + direct) |
| Unix/PAM Integration | No | No | No | No | Built-in (TPM-backed) |
| Passkeys/WebAuthn | Yes | Yes | Limited | Yes | Best-in-class |
| Admin UI | None (YAML files) | Full web UI | Full web UI | Full web UI | None (CLI) |
| Homelab Popularity | Very High | High | Medium | Low | Growing |
| Gateway API Support | v4.37+ | 2025.4+ | No | No | No |

## Detailed Analysis

### Authelia (Recommended)

- **Version**: v4.39+, OpenID Certified, Apache 2.0
- **Helm**: `https://charts.authelia.com` (traditional repo, not OCI). Most homelab users deploy via bjw-s app-template chart.
- **Envoy Gateway**: First-class support since v4.37.0 with dedicated documentation. Uses `SecurityPolicy` CRD with `extAuth.http` pointing to `/api/authz/ext-authz/`. Supports per-HTTPRoute and per-Gateway scoping.
- **GitOps**: All configuration (OIDC clients, access rules, users, MFA) is YAML file-driven. No GUI. Diffs cleanly in PRs.
- **Resources**: ~20 MB image, ~25-30 MB RAM. SQLite built-in (sufficient for homelab), optionally PostgreSQL + Redis for HA.
- **App Integration**: Forward auth protects apps without native OIDC (Sonarr, Radarr, Prowlarr, qBittorrent). OIDC for Grafana.
- **Community**: Most popular in onedr0p/cluster-template repos (coolguy1771/home-ops, AskAlice/lakewood-ops, bbangert/homelab-gitops).

**Cluster readiness**: Prowlarr, Radarr, and Sonarr already configured with `AUTH__METHOD: External`.

### Authentik (Runner-up)

- **Version**: v2025.12.3, actively maintained
- **Helm**: OCI chart at `oci://ghcr.io/goauthentik/helm/authentik` (fits OCIRepository pattern)
- **Envoy Gateway**: Supported via proxy outpost on port 9000. Known X-Forwarded-Proto bug with mobile browsers (fix expected). Gateway API HTTPRoute support added in 2025.4.
- **GitOps**: Mixed. Deployment is GitOps-compatible but app-level config (flows, providers, OIDC clients) lives in database. REST API and Terraform provider available for automation.
- **Resources**: ~600 MB-1 GB RAM, 2 containers (server + worker). Redis dependency removed in 2025.10.
- **Extra features**: Web admin UI, built-in LDAP server, SAML, Plex social login, browser-based RDP/SSH/VNC (RAC).
- **Community**: Well-represented in homelab Flux repos. Can share existing CloudNative-PG cluster.

Choose Authentik if you need a web UI, LDAP, SAML, or Plex integration.

### Keycloak (Not recommended)

- Enterprise-grade, heaviest option (~400+ MB RAM, JVM)
- No native Envoy Gateway support (requires oauth2-proxy)
- Partially GitOps-compatible via keycloak-config-cli
- Overkill for homelab use

### Zitadel (Not recommended)

- No forward auth support (requires oauth2-proxy bridge)
- No OCI Helm chart
- Low homelab adoption
- More suited to SaaS/startup environments

### Kanidm (Worth considering if RADIUS is needed)

- **Version**: v1.8.x, MPL-2.0, ~4,474 GitHub stars, 106+ contributors, quarterly releases
- **Helm**: OCI chart via Kaniop operator at `oci://ghcr.io/pando85/helm-charts/kaniop`
- **Architecture**: Single Rust binary with embedded database. No external PostgreSQL/Redis needed. ~80 MB RAM.
- **OIDC**: Built-in provider with mandatory PKCE, ES256 tokens (legacy RS256 available), scope/claim maps, RFC 9068 JWT
- **RADIUS**: Built-in container wrapping FreeRADIUS with Kanidm backend. WPA2-Enterprise (MSCHAPv2/PEAP), EAP-TLS, group-to-VLAN mapping. Isolated per-service credentials.
- **Passkeys/WebAuthn**: Best-in-class. Maintains `webauthn-rs` (used in Firefox). Security-audited by SUSE. Attestation support for restricting authenticator models.
- **SSH keys**: Built-in distribution with cached mode (survives network outages) and direct mode
- **Unix/POSIX**: PAM + nsswitch daemon with TPM-backed credential caching, auto home directory creation
- **LDAP**: Read-only gateway (intentional design -- not a write-capable LDAP server)
- **No SAML**, no upstream OIDC federation, no native forward-auth

**Kaniop Kubernetes Operator (v0.4.1)**:
- CRDs: `Kanidm`, `KanidmPersonAccount`, `KanidmGroup`, `KanidmOAuth2Client`, `KanidmServiceAccount`
- All declarable in Git and managed by Flux
- Supports HA with 2-node replication (all nodes accept writes, eventually consistent)
- ~50 GitHub stars -- early-stage but functional for homelab

**GitOps caveats**:
- OAuth2 client secrets are generated by Kanidm, not settable from Git (need bootstrap step or ExternalSecrets)
- Initial admin recovery requires imperative `kanidm recover-account admin` command
- User credentials (passkeys, passwords, RADIUS) are self-managed by users via WebUI
- Admin operations are CLI-only (no web admin panel)

**Envoy Gateway integration** (two options):
1. **oauth2-proxy as ext-auth** -- deploy oauth2-proxy with Kanidm as OIDC provider, use SecurityPolicy extAuth.http
2. **Envoy Gateway native OIDC SecurityPolicy** -- eliminates oauth2-proxy entirely, but less flexible for header injection

**Replaces**: LLDAP + Authelia (single service for OIDC + user store), standalone FreeRADIUS

**Choose Kanidm if**: You need RADIUS (WiFi WPA2-Enterprise, 802.1X, VPN auth), SSH key distribution, or Unix/PAM integration alongside OIDC. Accept the trade-off of needing oauth2-proxy for non-OIDC apps and being an early Kaniop adopter.

## Envoy Gateway v1.7.0 Blocker

**All SSO providers are affected.** Envoy Gateway v1.7.0 (bundled Envoy Proxy v1.37.0) strips the `Location` header from ext-auth denial responses, breaking redirect-based auth flows. See [envoyproxy/gateway#8202](https://github.com/envoyproxy/gateway/issues/8202).

**Workarounds:**
1. Pin Envoy Gateway to v1.6.x until the fix lands
2. Use EnvoyPatchPolicy to inject `allowed_client_headers` (workaround, if available)
3. Wait for v1.7.1 or v1.8.0

The proposed fix adds a `headersToDownstream` field to `SecurityPolicy`. Status: open, triaged.

## Implementation Notes for This Cluster

### Authelia deployment path

1. Deploy Authelia in a new `auth` or `security` namespace
2. Use bjw-s app-template chart (most common in cluster-template repos) or official Helm chart
3. Configure Envoy Gateway `SecurityPolicy` with `extAuth.http` pointing to Authelia
4. OIDC clients for Grafana defined in Authelia's YAML config
5. Forward auth for *arr apps via ext-authz endpoint
6. User storage: YAML file (small homelab) or LLDAP (if LDAP needed)
7. Database: SQLite (simplest) or CloudNative-PG (if HA required)

### Envoy Gateway SecurityPolicy example

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: authelia-auth
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: <app-route>
  extAuth:
    http:
      backendRef:
        name: authelia
        namespace: auth
        port: 9091
      headersToBackend:
        - cookie
        - authorization
      path: /api/authz/ext-authz/
```

### Kanidm deployment path

1. Deploy Kaniop operator via HelmRelease (`oci://ghcr.io/pando85/helm-charts/kaniop`)
2. Declare `Kanidm` cluster, `KanidmPersonAccount`, `KanidmGroup`, `KanidmOAuth2Client` CRDs in Git
3. Bootstrap: run `kanidm recover-account admin` once to set initial credentials
4. For OIDC apps (Grafana, Penpot, kubevirt-manager): configure OAuth2 clients via Kaniop CRDs
5. For non-OIDC apps (*arr stack): deploy oauth2-proxy with Kanidm as OIDC provider, or use Envoy Gateway native OIDC SecurityPolicy
6. For RADIUS: deploy `kanidm/radius` container, configure WiFi APs as RADIUS clients
7. OAuth2 secrets: retrieve via `kanidm system oauth2 show-basic-secret`, store in SOPS-encrypted secrets

### Envoy Gateway native OIDC SecurityPolicy example (no oauth2-proxy needed)

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
      issuer: "https://idm.${SECRET_DOMAIN}/oauth2/openid/<client-name>"
    clientID: "<client-name>"
    clientSecret:
      name: "<client-secret-name>"
    redirectURL: "https://<app>.${SECRET_DOMAIN}/oauth2/callback"
```

## References

- [Authelia Envoy Gateway Integration](https://www.authelia.com/integration/kubernetes/envoy/gateway/)
- [Authelia OIDC for Envoy Gateway](https://www.authelia.com/integration/openid-connect/clients/envoy-gateway/)
- [Authelia Grafana OIDC Guide](https://www.authelia.com/integration/openid-connect/clients/grafana/)
- [Authentik Helm Chart (OCI)](https://artifacthub.io/packages/helm/goauthentik/authentik)
- [Authentik Envoy Docs](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_envoy/)
- [Authentik Redis Removal (2025.10)](https://goauthentik.io/blog/2025-11-13-we-removed-redis/)
- [Envoy Gateway External Authorization](https://gateway.envoyproxy.io/docs/tasks/security/ext-auth/)
- [Envoy Gateway OIDC Documentation](https://gateway.envoyproxy.io/docs/tasks/security/oidc/)
- [Envoy Gateway v1.7.0 ext-auth redirect bug](https://github.com/envoyproxy/gateway/issues/8202)
- [Kanidm OAuth2 Documentation](https://kanidm.github.io/kanidm/stable/integrations/oauth2.html)
- [Kanidm RADIUS Documentation](https://kanidm.github.io/kanidm/stable/integrations/radius.html)
- [Kanidm SSH Key Distribution](https://kanidm.github.io/kanidm/stable/integrations/ssh_key_distribution.html)
- [Kaniop Kubernetes Operator](https://github.com/pando85/kaniop)
- [Kanidm Forward Auth Feature Request](https://github.com/kanidm/kanidm/issues/2774)
- [kubesearch.dev - Authelia deployments](https://kubesearch.dev/hr/charts.authelia.com-authelia)
- [kubesearch.dev - Authentik deployments](https://kubesearch.dev/hr/charts.goauthentik.io-authentik)
