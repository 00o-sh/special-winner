# SSO Provider Research for Kubernetes Homelab (GitOps-Friendly)

> Researched 2026-02-07. Stack: Flux CD, Envoy Gateway, CloudNative-PG, Talos Linux, onedr0p/cluster-template.

## Recommendation: Authelia

Authelia is the best fit for this cluster due to native Envoy Gateway support, fully declarative YAML configuration (GitOps-native), minimal resource usage (~30 MB RAM), and strong adoption in the cluster-template community.

## Comparison Matrix

| Feature | Authelia | Authentik | Keycloak | Zitadel | Kanidm |
|---|---|---|---|---|---|
| RAM (baseline) | ~30 MB | ~600 MB-1 GB | ~400+ MB | ~512 MB-1 GB | Low (Rust) |
| OCI Helm Chart | No (traditional repo) | Yes (ghcr.io) | Yes (Bitnami) | No (traditional) | Yes (Kaniop) |
| Envoy Gateway ext-auth | Native (first-class) | Supported (minor bug) | Via oauth2-proxy | Via oauth2-proxy | Via oauth2-proxy |
| Forward Auth | Native (core feature) | Native (proxy outpost) | Via oauth2-proxy | Via oauth2-proxy | Via oauth2-proxy |
| GitOps Config | Excellent (YAML) | Mixed (GUI + API) | Partial (config-cli) | API/Terraform | CLI / Kaniop CRDs |
| PostgreSQL | Optional | Required | Required | Required | Not needed |
| OIDC Provider | Yes (certified) | Yes | Yes | Yes | Yes |
| SAML | No | Yes | Yes | Via brokering | No |
| LDAP Server | No (pairs with LLDAP) | Yes (built-in) | Yes (federation) | No | No |
| Admin UI | None (YAML files) | Full web UI | Full web UI | Full web UI | None (CLI) |
| Homelab Popularity | Very High | High | Medium | Low | Very Low |
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

### Kanidm (Not recommended)

- Immature Kubernetes story
- No forward auth (requires oauth2-proxy)
- Very low adoption in Flux/GitOps community
- Interesting Rust-based option for the future

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

## References

- [Authelia Envoy Gateway Integration](https://www.authelia.com/integration/kubernetes/envoy/gateway/)
- [Authelia OIDC for Envoy Gateway](https://www.authelia.com/integration/openid-connect/clients/envoy-gateway/)
- [Authelia Grafana OIDC Guide](https://www.authelia.com/integration/openid-connect/clients/grafana/)
- [Authentik Helm Chart (OCI)](https://artifacthub.io/packages/helm/goauthentik/authentik)
- [Authentik Envoy Docs](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_envoy/)
- [Authentik Redis Removal (2025.10)](https://goauthentik.io/blog/2025-11-13-we-removed-redis/)
- [Envoy Gateway External Authorization](https://gateway.envoyproxy.io/docs/tasks/security/ext-auth/)
- [kubesearch.dev - Authelia deployments](https://kubesearch.dev/hr/charts.authelia.com-authelia)
- [kubesearch.dev - Authentik deployments](https://kubesearch.dev/hr/charts.goauthentik.io-authentik)
