# Kanidm Identity Provider

Kanidm is a Rust-based identity management server providing OIDC, RADIUS, and SSH key distribution.

Available at `https://auth.00o.sh`

## Architecture

```
identity/kanidm/
├── app/          # Kaniop operator (Helm chart)
├── instance/     # Kanidm CR (server deployed and managed by Kaniop)
├── config/       # Identity resources (persons, groups, OAuth2 clients)
└── ks.yaml       # Flux Kustomizations (operator -> instance -> config)
```

## Post-Deploy Bootstrap

Account recovery uses `kanidmd` (the server binary, available in the server pod).
Day-to-day management uses the `kanidm` CLI (available via the `kanidm/tools` image).

```bash
# 1. Recover admin account (runs kanidmd inside the server pod)
kubectl -n identity exec -it sts/kanidm-default -c kanidm -- kanidmd recover-account admin

# 2. Recover idm_admin account (for day-to-day identity management)
kubectl -n identity exec -it sts/kanidm-default -c kanidm -- kanidmd recover-account idm_admin
```

A persistent `tools` sidecar container runs alongside the server with the `kanidm` CLI
pre-configured to connect via localhost. Session tokens persist across commands.

```bash
# Open a shell in the tools container
kubectl -n identity exec -it sts/kanidm-default -c tools -- sh

# Then inside the shell:
kanidm login -D admin
kanidm self whoami
kanidm person list
```

Or run one-off commands directly:

```bash
kubectl -n identity exec -it sts/kanidm-default -c tools -- kanidm self whoami
```

### 3. Set up user credentials

New person accounts created via Kaniop CRDs have no credentials. Generate a
credential reset token so the user can set their password and passkeys:

```bash
# Login as idm_admin first (requires -it for TTY)
kubectl -n identity exec -it sts/kanidm-default -c tools -- kanidm login --name idm_admin

# Generate a credential reset link for the user
kubectl -n identity exec -it sts/kanidm-default -c tools -- kanidm person credential create-reset-token <username> --name idm_admin
```

Open the returned URL in a browser to set up the user's password/passkeys.
This is required before the user can log in via OIDC.

## Managing Users, Groups & OAuth2 Clients

After bootstrap, declare resources as Kaniop CRDs in a `config/` directory:

```yaml
# KanidmPersonAccount
apiVersion: kaniop.rs/v1beta1
kind: KanidmPersonAccount
metadata:
  name: alice
spec:
  kanidmRef:
    name: kanidm
  personAttributes:
    displayname: Alice
    mail:
      - alice@example.com
```

```yaml
# KanidmGroup
apiVersion: kaniop.rs/v1beta1
kind: KanidmGroup
metadata:
  name: app-users
spec:
  kanidmRef:
    name: kanidm
  members:
    - alice
```

```yaml
# KanidmOAuth2Client
apiVersion: kaniop.rs/v1beta1
kind: KanidmOAuth2Client
metadata:
  name: grafana
spec:
  kanidmRef:
    name: kanidm
  displayname: Grafana
  origin: "https://grafana.00o.sh"
  redirectUrl: "https://grafana.00o.sh/login/generic_oauth"
```

## Retrieving OAuth2 Secrets

Kaniop automatically creates a Kubernetes secret for each `KanidmOAuth2Client`:

```
<client-name>-kanidm-oauth2-credentials   (keys: CLIENT_ID, CLIENT_SECRET)
```

These secrets live in the `identity` namespace. For cross-namespace access
(e.g., Penpot in `utils`), a `kubernetes-identity` ClusterSecretStore is
configured so ExternalSecrets in other namespaces can read them directly:

```yaml
# In the consuming app's ExternalSecret
data:
  - secretKey: OIDC_CLIENT_SECRET
    sourceRef:
      storeRef:
        name: kubernetes-identity
        kind: ClusterSecretStore
    remoteRef:
      key: <client-name>-kanidm-oauth2-credentials
      property: CLIENT_SECRET
```

No manual secret copying or 1Password storage needed.

## Adding SSO to Applications

### Option 1: Apps with native OIDC support (Grafana, Penpot, etc.)

1. Create a `KanidmOAuth2Client` CRD (see above)
2. Create a `KanidmGroup` for authorized users and add a scope map
3. Use the `kubernetes-identity` ClusterSecretStore to pull the client secret (see above)
4. Configure the app's OIDC settings

**PKCE note:** Kanidm requires PKCE (S256) by default. Apps that support PKCE
(e.g., Grafana) should use it. For apps that don't support PKCE (e.g., Penpot),
add `allowInsecureClientDisablePkce: true` to the `KanidmOAuth2Client` spec.

```yaml
# Example: Grafana HelmRelease values
env:
  GF_AUTH_GENERIC_OAUTH_ENABLED: "true"
  GF_AUTH_GENERIC_OAUTH_NAME: Kanidm
  GF_AUTH_GENERIC_OAUTH_CLIENT_ID: grafana
  GF_AUTH_GENERIC_OAUTH_SCOPES: openid email profile groups
  GF_AUTH_GENERIC_OAUTH_AUTH_URL: https://auth.00o.sh/ui/oauth2
  GF_AUTH_GENERIC_OAUTH_TOKEN_URL: https://auth.00o.sh/oauth2/token
  GF_AUTH_GENERIC_OAUTH_API_URL: https://auth.00o.sh/oauth2/openid/grafana/userinfo
  GF_AUTH_GENERIC_OAUTH_USE_PKCE: "true"
  GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH: "contains(groups[*], 'grafana-admin') && 'Admin' || 'Viewer'"
envFrom:
  - secretRef:
      name: grafana-oauth-secret  # contains GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
```

### Option 2: Apps without OIDC support (Sonarr, Radarr, Prowlarr, etc.)

These apps need an auth proxy in front of them. Two approaches:

**A) Envoy Gateway native OIDC SecurityPolicy (simpler, no extra deployment):**

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: sonarr-oidc
  namespace: media
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: sonarr
  oidc:
    provider:
      issuer: "https://auth.00o.sh/oauth2/openid/sonarr"
    clientID: "sonarr"
    clientSecret:
      name: "sonarr-oauth-secret"
    redirectURL: "https://sonarr.00o.sh/oauth2/callback"
    logoutPath: "/oauth2/sign_out"
```

**B) oauth2-proxy as ext-auth (more flexible, header injection):**

Deploy oauth2-proxy with Kanidm as the OIDC provider, then use a SecurityPolicy
with ext-auth pointing to oauth2-proxy. This gives you X-Forwarded-User headers
and group-based access control at the proxy layer.

### Option 3: RADIUS (WiFi WPA2-Enterprise, 802.1X, VPN)

Deploy the `kanidm/radius` container alongside the server. Configure your
access points (UniFi, etc.) as RADIUS clients. Users authenticate with their
Kanidm RADIUS credentials (separate from their primary password).

## Endpoints

| Service | Port | Description |
|---------|------|-------------|
| HTTPS | 8443 | Web UI + OIDC provider |
| LDAPS | 3636 | Read-only LDAP gateway |

## OIDC Endpoints

| Endpoint | URL |
|----------|-----|
| Discovery | `https://auth.00o.sh/oauth2/openid/<client>/.well-known/openid-configuration` |
| Authorization | `https://auth.00o.sh/ui/oauth2` |
| Token | `https://auth.00o.sh/oauth2/token` |
| Userinfo | `https://auth.00o.sh/oauth2/openid/<client>/userinfo` |

## Useful Commands

All CLI commands use the `kanidm-cli` alias defined in the bootstrap section above.

```bash
# List all persons
kanidm-cli kanidm person list

# List all groups
kanidm-cli kanidm group list

# List OAuth2 clients
kanidm-cli kanidm system oauth2 list

# Create OAuth2 client (imperative, prefer Kaniop CRDs instead)
kanidm-cli kanidm system oauth2 create <name> <displayname> <origin>

# Add redirect URL
kanidm-cli kanidm system oauth2 add-redirect-url <name> <url>

# Add scope map (grant scopes to a group)
kanidm-cli kanidm system oauth2 update-scope-map <client> <group> openid email profile groups

# Check server status
curl -sk https://auth.00o.sh/status
```
