# Post-Installation

## Verification

### Check Cilium

```sh
cilium status
```

### Check Flux

```sh
flux check
flux get sources git flux-system
flux get ks -A
flux get hr -A
```

!!! tip
    Run `task reconcile` to force Flux to sync immediately.

### Check Connectivity

```sh
# Test gateway ports (replace variables with actual values)
nmap -Pn -n -p 443 ${cluster_gateway_addr} ${cloudflare_gateway_addr} -vv
```

### Check DNS

```sh
# Should resolve to your Cloudflare gateway address
dig @${cluster_dns_gateway_addr} echo.${cloudflare_domain}
```

### Check Certificates

```sh
kubectl -n network describe certificates
```

## Configure GitHub Webhook

For push-triggered reconciliation (instead of polling):

1. Get the webhook path:

    ```sh
    kubectl -n flux-system get receiver github-webhook \
      --output=jsonpath='{.status.webhookPath}'
    ```

2. Build the full URL:

    ```
    https://flux-webhook.${cloudflare_domain}/hook/<webhook-path>
    ```

3. In GitHub repository settings, go to **Settings > Webhooks > Add webhook**:
    - **URL**: The full webhook URL from above
    - **Secret**: Contents of `github-push-token.txt`
    - **Content type**: `application/json`
    - **Events**: Just the push event

## Configure Home DNS (Split DNS)

The `k8s_gateway` service provides DNS resolution for cluster services. Configure your home DNS server to forward queries for your domain to `${cluster_dns_gateway_addr}`.

This enables accessing internal services like `grafana.yourdomain.com` from any device on your network.

## Public vs Private Access

| Gateway | Use Case | Configuration |
|---------|----------|---------------|
| `envoy-external` | Public internet access | Routes through Cloudflare Tunnel |
| `envoy-internal` | Private network only | Accessible via split DNS |

By default, only `echo` and `flux-webhook` are publicly accessible. To make additional apps public, set the correct gateway on their HTTPRoute.

## Clean Up Templates

Once the cluster is stable and you no longer need `task configure`:

```sh
task template:tidy
git add -A
git commit -m "chore: tidy up"
git push
```

This removes the `templates/` directory and template-related files.
