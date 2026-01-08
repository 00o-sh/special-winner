# Observability Stack - 1Password Secrets Setup

This document lists all secrets required for the observability stack to function properly.

## Required 1Password Keys

### 1. `alertmanager` Key

Create a new 1Password item named `alertmanager` with the following fields:

| Field Name | Value | Description |
|------------|-------|-------------|
| `DISCORD_WEBHOOK_URL` | `https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN` | Discord webhook URL for Alertmanager notifications. Get this from Discord: Server Settings → Integrations → Webhooks → New Webhook |
| `BUDDY_HEARTBEAT_TOKEN` | `c8d8f220-ddd7-4fa9-9807-e19c531a45dd` | **IMPORTANT:** This token authenticates Alertmanager's heartbeat requests to Gatus. Must match the same field in the `gatus` key. |

**Note:** The `BUDDY_HEARTBEAT_URL` is automatically constructed from `BUDDY_STATUS_HOSTNAME` in the gatus key.

---

### 2. `gatus` Key

Create a new 1Password item named `gatus` with the following fields:

| Field Name | Value | Description |
|------------|-------|-------------|
| `BUDDY_DISCORD_WEBHOOK_URL` | `https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN` | Discord webhook URL for Gatus buddy monitoring alerts. Can be the same webhook as alertmanager or a different one. |
| `BUDDY_HEARTBEAT_TOKEN` | `c8d8f220-ddd7-4fa9-9807-e19c531a45dd` | **IMPORTANT:** Must be the exact same value as in the `alertmanager` key. This token is used to validate heartbeat requests. |
| `BUDDY_STATUS_HOSTNAME` | `status.00o.sh` | The hostname where Gatus status page is accessible. This is used to construct the heartbeat URL. |

---

### 3. `grafana` Key

Create a new 1Password item named `grafana` with the following fields:

| Field Name | Value | Description |
|------------|-------|-------------|
| `GF_SECURITY_ADMIN_PASSWORD` | `PSXiLtlf472Gn8dJb8S1/DOf/eObBIsGr5u+IJpfI8s=` | Grafana admin user password. Save this securely - you'll need it to log into Grafana at grafana.00o.sh |

**Default username:** `admin`

---

## Discord Webhook Setup

To create Discord webhook URLs:

1. Open Discord and navigate to your server
2. Go to Server Settings → Integrations → Webhooks
3. Click "New Webhook"
4. Name it (e.g., "Alertmanager" or "Gatus")
5. Select the channel where you want notifications
6. Copy the webhook URL
7. Paste it into the appropriate 1Password field

You can use:
- The same webhook for both `DISCORD_WEBHOOK_URL` and `BUDDY_DISCORD_WEBHOOK_URL` (all alerts go to one channel)
- Different webhooks to separate critical alerts from buddy monitoring alerts

---

## Critical Notes

⚠️ **BUDDY_HEARTBEAT_TOKEN must match in both keys**

The `BUDDY_HEARTBEAT_TOKEN` field must have the **exact same value** in both:
- `alertmanager` key
- `gatus` key

This is because:
- Alertmanager sends a Watchdog alert every 2 minutes to Gatus
- The token in the URL authenticates this request
- Gatus validates the token against its configuration
- If tokens don't match, the buddy heartbeat will fail

---

## How Buddy Heartbeat Works

The "buddy" system monitors the monitoring system itself (dead man's switch):

1. **Prometheus** generates a special "Watchdog" alert that is always firing
2. **Alertmanager** receives this alert and routes it to the buddy-heartbeat webhook
3. The webhook sends a request to: `https://status.00o.sh/api/v1/endpoints/buddy_heartbeat/external?success=true&token=BUDDY_HEARTBEAT_TOKEN`
4. **Gatus** receives the heartbeat and resets its timer
5. If Gatus doesn't receive a heartbeat for 5 minutes, it sends a Discord alert that the monitoring system is down

This ensures you're notified if Prometheus or Alertmanager stops working.

---

## Verification

After creating these secrets in 1Password:

1. Wait for external-secrets-operator to sync (usually < 1 minute)
2. Check that secrets were created:
   ```bash
   kubectl get secrets -n observability | grep -E '(gatus-secret|alertmanager-secret|grafana-admin)'
   ```

3. Check external-secrets status:
   ```bash
   kubectl get externalsecrets -n observability
   ```

All should show `SecretSynced: True`

---

## Summary

**Total 1Password keys needed:** 3
- `alertmanager` (2 fields)
- `gatus` (3 fields)
- `grafana` (1 field)

**Secrets you need to provide:**
- 1-2 Discord webhook URLs (can reuse the same one)

**Generated secrets (provided above):**
- ✅ BUDDY_HEARTBEAT_TOKEN: `c8d8f220-ddd7-4fa9-9807-e19c531a45dd`
- ✅ GF_SECURITY_ADMIN_PASSWORD: `PSXiLtlf472Gn8dJb8S1/DOf/eObBIsGr5u+IJpfI8s=`
