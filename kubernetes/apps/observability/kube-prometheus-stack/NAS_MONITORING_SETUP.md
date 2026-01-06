# TrueNAS SCALE Monitoring Setup

This observability stack expects certain exporters to be running on your TrueNAS SCALE (`nas.3226texas.com`) to collect metrics.

## Required Exporters on TrueNAS SCALE

### 1. Node Exporter (Required)
**Port:** 9100
**Purpose:** Basic system metrics (CPU, memory, disk, network)

#### Option A: Via TrueNAS Apps (Recommended)

1. Go to **Apps** in TrueNAS SCALE UI
2. Click **Discover Apps** or **Custom App**
3. Deploy a Prometheus Node Exporter container

#### Option B: Via CLI
```bash
# SSH into TrueNAS
ssh admin@nas.3226texas.com

# Create directory for the exporter
mkdir -p /mnt/tank/.system/node-exporter
cd /mnt/tank/.system/node-exporter

# Download node exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.8.2.linux-amd64.tar.gz
cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/

# Create systemd service
cat > /etc/systemd/system/node-exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable node-exporter
systemctl start node-exporter
systemctl status node-exporter
```

### 2. SMARTCTL Exporter (Optional but Recommended)
**Port:** 9633
**Purpose:** Disk health monitoring (SMART data)

**TrueNAS SCALE already has `smartctl` installed!**

#### Installation:
```bash
# SSH into TrueNAS
ssh admin@nas.3226texas.com

# Download smartctl_exporter
cd /mnt/tank/.system
wget https://github.com/prometheus-community/smartctl_exporter/releases/download/v0.12.0/smartctl_exporter-0.12.0.linux-amd64.tar.gz
tar xvfz smartctl_exporter-0.12.0.linux-amd64.tar.gz
cp smartctl_exporter-0.12.0.linux-amd64/smartctl_exporter /usr/local/bin/

# Create systemd service
cat > /etc/systemd/system/smartctl-exporter.service <<'EOF'
[Unit]
Description=Prometheus SMARTCTL Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/smartctl_exporter
User=root
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable smartctl-exporter
systemctl start smartctl-exporter
systemctl status smartctl-exporter
```

## Verification

Once exporters are running on the NAS, verify they're accessible:

```bash
# Test from your local machine
curl http://nas.3226texas.com:9100/metrics  # Should return metrics
curl http://nas.3226texas.com:9633/metrics  # Should return disk metrics
```

## TrueNAS SCALE Firewall Configuration

TrueNAS SCALE typically doesn't have a firewall enabled by default, but if you have one configured:

1. Go to **System Settings** → **Services** in the TrueNAS UI
2. Ensure ports 9100 and 9633 are allowed from your Kubernetes network

**Or via CLI:**
```bash
# If using firewalld
firewall-cmd --permanent --add-port=9100/tcp
firewall-cmd --permanent --add-port=9633/tcp
firewall-cmd --reload
```

## What Gets Monitored

### From Node Exporter:
- CPU usage and load
- Memory usage
- Disk space and I/O
- Network traffic
- System uptime
- File system statistics

### From SMARTCTL Exporter:
- Disk health status
- Reallocated sectors
- Temperature
- Power-on hours
- Pending sectors
- SMART test results

## Grafana Dashboards

After setup, import these recommended Grafana dashboards:
- **Node Exporter Full**: Dashboard ID 1860
- **SMART Disk Monitoring**: Dashboard ID 10530

## Troubleshooting

**Prometheus not scraping NAS:**
1. **Check exporters are running:**
   ```bash
   systemctl status node-exporter smartctl-exporter
   ```

2. **Test locally on NAS:**
   ```bash
   curl http://localhost:9100/metrics
   curl http://localhost:9633/metrics
   ```

3. **Verify network connectivity from cluster:**
   ```bash
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://nas.3226texas.com:9100/metrics
   ```

4. **Check Prometheus targets:** Visit https://prometheus.00o.sh/targets

5. **Check DNS resolution:**
   ```bash
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- nslookup nas.3226texas.com
   ```

**Exporters not starting after TrueNAS reboot:**
Services should auto-start via systemd. Check with:
```bash
systemctl status node-exporter smartctl-exporter
```

**High memory alert being silenced:**
There's a silence configured for `NodeMemoryHighUtilization` on the NAS at `nas.3226texas.com:9100`. TrueNAS typically uses a lot of memory for ZFS ARC cache, which is normal. If you want to remove this silence, edit `kubernetes/apps/observability/silence-operator/silences/silences.yaml`.

**After TrueNAS SCALE Update:**
TrueNAS SCALE updates may remove custom systemd services. After major updates, you may need to:
- Verify services are still enabled: `systemctl status node-exporter smartctl-exporter`
- Reinstall if needed (follow installation steps above)
- Consider using a TrueNAS Apps deployment instead for persistence
