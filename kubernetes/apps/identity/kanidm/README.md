# Kanidm Identity Provider

Kanidm is a Rust-based identity management server providing OIDC, RADIUS, and SSH key distribution.

Available at `https://auth.00o.sh`

## Architecture

```
identity/kanidm/
├── app/          # Kaniop operator (Helm chart)
├── instance/     # Kanidm CR (server deployed and managed by Kaniop)
├── config/       # Identity resources (persons, groups, OAuth2 clients, secrets)
└── ks.yaml       # Flux Kustomizations (operator -> instance -> config)
```

**Flux dependency chain:** `kaniop` (operator) -> `kanidm` (instance + TLS cert) -> `kanidm-config` (persons, groups, OAuth2 clients)

The Kanidm instance runs as a StatefulSet with a single container:
- **kanidm**: The Kanidm server (port 8443 HTTPS, 3636 LDAPS)

A separate CronJob (`kanidm-backup-sync`) runs hourly to sync online backups to Garage S3.

> **Why a single container?** Kaniop's pod exec uses `AttachParams::default()` which
> does not specify a container name. Kubernetes returns HTTP 400 on exec requests to
> multi-container pods without a container parameter, causing the
> `UpgradeConnection(ProtocolSwitch(400))` error. Keeping the pod single-container
> avoids this upstream limitation.

## Post-Deploy Bootstrap

### 1. Recover admin accounts

Account recovery requires `kanidmd` (the server binary) running inside the server container.

```bash
# Recover admin account
kubectl -n identity exec -it sts/kanidm-default -c kanidm -- kanidmd recover-account admin

# Recover idm_admin account (for day-to-day identity management)
kubectl -n identity exec -it sts/kanidm-default -c kanidm -- kanidmd recover-account idm_admin
```

> **Note:** Kaniop automates admin password recovery by exec'ing into the pod.
> This requires the pod to have a single container (see Architecture section above).
> Admin passwords are also stored in 1Password and injected via ExternalSecret.

### 2. Use the kanidm CLI via kubectl exec

The `kanidm` CLI is available inside the server container. **Always use `-it` flags** —
the CLI requires a TTY for interactive login prompts.

```bash
# Open a shell in the kanidm container
kubectl -n identity exec -it sts/kanidm-default -- sh

# Or run one-off commands directly
kubectl -n identity exec -it sts/kanidm-default -- kanidm login -D admin
kubectl -n identity exec -it sts/kanidm-default -- kanidm person list
```

### 3. Set up user credentials

New person accounts created via Kaniop CRDs have **no credentials**. Users cannot log in
(including via OIDC) until credentials are set up. Generate a credential reset token:

```bash
# Login as idm_admin first (requires -it for TTY)
kubectl -n identity exec -it sts/kanidm-default -- kanidm login --name idm_admin

# Generate a credential reset link for the user
kubectl -n identity exec -it sts/kanidm-default -- kanidm person credential create-reset-token <username> --name idm_admin
```

Open the returned URL in a browser to set up the user's password and passkeys.
**This is required before the user can log in via OIDC** — without credentials,
Kanidm returns an "invalid credential state" error during the OAuth2 flow.

## Managing Users, Groups & OAuth2 Clients

Declare resources as Kaniop CRDs in the `config/` directory:

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
# KanidmGroup (controls OAuth2 access via scope maps)
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
  name: myapp
spec:
  kanidmRef:
    name: kanidm
  displayname: My App
  origin: "https://myapp.00o.sh"
  redirectUrl:
    - "https://myapp.00o.sh/callback"
  scopeMap:
    - group: app-users
      scopes:
        - openid
        - email
        - profile
```

## Admin Passwords Secret

Kaniop expects a secret with **uppercase** keys:

| Key | Value |
|-----|-------|
| `ADMIN_USERNAME` | `admin` |
| `ADMIN_PASSWORD` | (from 1Password) |
| `IDM_ADMIN_USERNAME` | `idm_admin` |
| `IDM_ADMIN_PASSWORD` | (from 1Password) |

These are stored in 1Password under the `kanidm` item and injected via
`config/externalsecret.yaml`. **Do not use lowercase key names** — Kaniop
will fail with "missing password for idm_admin".

## OAuth2 Secrets (Automated Cross-Namespace)

Kaniop automatically creates a Kubernetes secret for each `KanidmOAuth2Client`:

```
<client-name>-kanidm-oauth2-credentials   (keys: CLIENT_ID, CLIENT_SECRET)
```

These secrets live in the `identity` namespace. For cross-namespace access
(e.g., Penpot in `utils`), a `kubernetes-identity` ClusterSecretStore is
configured so ExternalSecrets in other namespaces can read them directly:

```yaml
# In the consuming app's ExternalSecret, override the store for this one key:
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

The `kubernetes-identity` ClusterSecretStore uses the External Secrets `kubernetes`
provider to read secrets from the `identity` namespace via the `external-secrets` SA
(which has cluster-wide access via the Helm chart's RBAC).

No manual secret copying or 1Password storage needed. Consuming apps should add
`kanidm-config` as a Flux dependency to ensure the OAuth2 secret exists before
the ExternalSecret tries to read it.

## Adding SSO to Applications

### Option 1: Apps with native OIDC support (Grafana, Penpot, etc.)

1. Create a `KanidmOAuth2Client` CRD with a scope map
2. Create a `KanidmGroup` for authorized users
3. Use the `kubernetes-identity` ClusterSecretStore to pull the client secret
4. Configure the app's OIDC settings pointing to Kanidm's endpoints
5. Add `kanidm-config` as a Flux dependency in the app's `ks.yaml`

**PKCE:** Kanidm requires PKCE (S256) by default. Apps that support PKCE
(e.g., Grafana) should use it. For apps that don't support PKCE (e.g., Penpot),
add `allowInsecureClientDisablePkce: true` to the `KanidmOAuth2Client` spec.

**Redirect URIs:** Kanidm requires an **exact match** on redirect URIs.
Check the app's actual callback URL carefully — a single path segment difference
will cause an `InvalidState` error. Kanidm's server logs show the exact mismatch:

```
Invalid OAuth2 redirect_uri (must be an exact match) - got <actual-url>
```

#### Penpot OIDC Configuration (working example)

OAuth2 client (`config/oauth2-penpot.yaml`):
```yaml
apiVersion: kaniop.rs/v1beta1
kind: KanidmOAuth2Client
metadata:
  name: penpot
spec:
  kanidmRef:
    name: kanidm
  displayname: Penpot
  origin: "https://penpot.00o.sh"
  allowInsecureClientDisablePkce: true  # Penpot doesn't support PKCE
  redirectUrl:
    - "https://penpot.00o.sh/api/auth/oidc/callback"  # NOT /api/auth/oauth/oidc/callback
  scopeMap:
    - group: penpot-users
      scopes:
        - openid
        - email
        - profile
```

Penpot backend env vars:
```yaml
PENPOT_FLAGS: enable-registration enable-login-with-password enable-login-with-oidc disable-email-verification
PENPOT_OIDC_CLIENT_ID: penpot
PENPOT_OIDC_CLIENT_SECRET: (from kubernetes-identity ClusterSecretStore)
PENPOT_OIDC_BASE_URI: https://auth.00o.sh/oauth2/openid/penpot
PENPOT_OIDC_AUTH_URI: https://auth.00o.sh/ui/oauth2
PENPOT_OIDC_TOKEN_URI: https://auth.00o.sh/oauth2/token
PENPOT_OIDC_USER_URI: https://auth.00o.sh/oauth2/openid/penpot/userinfo
PENPOT_OIDC_SCOPES: "openid email profile"
PENPOT_OIDC_NAME_ATTR: name
PENPOT_OIDC_EMAIL_ATTR: email
```

Penpot frontend also needs: `PENPOT_FLAGS: enable-login-with-oidc` (both backend and frontend must have this flag).

#### Grafana OIDC Configuration (example)

```yaml
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

These apps need an auth proxy. Two approaches:

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

## Backups

Kanidm's built-in online backup runs daily at 02:00 UTC, keeping 7 versions in `/data/backups/`.
The `kanidm-backup-sync` CronJob syncs these to Garage S3 (`s3://kanidm/backups/`) hourly via `aws s3 sync`.
The CronJob uses podAffinity to schedule on the same node as the kanidm StatefulSet,
allowing it to mount the RWO PVC concurrently.

S3 credentials are stored in 1Password and injected via `config/externalsecret-s3.yaml`.

> **Why not Volsync?** The Kaniop operator controls PVC naming for the StatefulSet,
> which creates tight coupling that breaks disaster recovery workflows. Using Kanidm's
> native backup + S3 sync is more portable and doesn't depend on PVC naming conventions.

## OIDC Endpoints

| Endpoint | URL |
|----------|-----|
| Discovery | `https://auth.00o.sh/oauth2/openid/<client>/.well-known/openid-configuration` |
| Authorization | `https://auth.00o.sh/ui/oauth2` |
| Token | `https://auth.00o.sh/oauth2/token` |
| Userinfo | `https://auth.00o.sh/oauth2/openid/<client>/userinfo` |

| Service | Port | Description |
|---------|------|-------------|
| HTTPS | 8443 | Web UI + OIDC provider |
| LDAPS | 3636 | Read-only LDAP gateway |

## Troubleshooting

### `InvalidState` error during OAuth2 flow

Check in order:
1. **Redirect URI mismatch** — Most common cause. Check Kanidm server logs for the exact mismatch:
   ```bash
   kubectl -n identity logs sts/kanidm-default -c kanidm | grep "redirect_uri"
   ```
2. **PKCE not disabled** — If the app doesn't support PKCE, add `allowInsecureClientDisablePkce: true`
3. **User has no credentials** — New person accounts from CRDs have no password/passkeys. Generate a reset token (see bootstrap step 3)

### "missing password for idm_admin in secret"

Kaniop expects **uppercase** secret keys: `ADMIN_PASSWORD`, `IDM_ADMIN_PASSWORD`, etc.
Check the ExternalSecret template — do not use lowercase `admin`/`idm_admin` as keys.

### `UpgradeConnection(ProtocolSwitch(400))` in Kaniop logs

Caused by kaniop using `AttachParams::default()` for pod exec, which omits the
container name. Kubernetes returns HTTP 400 when exec targets a multi-container
pod without specifying a container. Fix: ensure the Kanidm CR has no extra
`containers` (sidecars) so the pod remains single-container.

### OIDC login button not showing

Ensure **both** the backend and frontend have `enable-login-with-oidc` in their
`PENPOT_FLAGS` (or equivalent). If the HelmRelease rolled back due to a missing
secret, force reconcile after the secret is populated:
```bash
flux reconcile hr <app> -n <namespace> --force
```

### OAuth2 client secret not syncing

Verify the Kaniop config Flux Kustomization has reconciled and the secret exists:
```bash
kubectl -n identity get secret <client>-kanidm-oauth2-credentials
```

Then check the consuming app's ExternalSecret status:
```bash
kubectl -n <namespace> get externalsecret <name> -o yaml
```

## Useful Commands

```bash
# Open a shell in the kanidm container
kubectl -n identity exec -it sts/kanidm-default -- sh

# Login as admin
kubectl -n identity exec -it sts/kanidm-default -- kanidm login -D admin

# List persons / groups / OAuth2 clients
kubectl -n identity exec -it sts/kanidm-default -- kanidm person list
kubectl -n identity exec -it sts/kanidm-default -- kanidm group list
kubectl -n identity exec -it sts/kanidm-default -- kanidm system oauth2 list

# Check server status
curl -sk https://auth.00o.sh/status

# Check OIDC discovery for a client
curl -sk https://auth.00o.sh/oauth2/openid/<client>/.well-known/openid-configuration | jq

# View Kanidm server logs (useful for redirect_uri debugging)
kubectl -n identity logs sts/kanidm-default -c kanidm --tail=50

# View Kaniop operator logs
kubectl -n identity logs deploy/kaniop -f
```

## Known Issues

- **Kaniop exec fails with multi-container pods** (`UpgradeConnection(ProtocolSwitch(400))`): Kaniop uses `AttachParams::default()` without specifying a container name. Do not add sidecar containers to the Kanidm CR — use CronJobs or separate deployments instead.
- **PushSecret not supported**: 1Password Connect provider doesn't support PushSecret for pushing Kaniop-managed secrets to 1Password. Future migration to 1Password SDK provider would enable this.
