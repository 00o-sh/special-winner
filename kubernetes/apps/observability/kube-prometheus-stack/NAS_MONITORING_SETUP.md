# NAS Monitoring Setup

This observability stack expects certain exporters to be running on your NAS (`nas.3226texas.com`) to collect metrics.

## Required Exporters on NAS

### 1. Node Exporter (Required)
**Port:** 9100
**Purpose:** Basic system metrics (CPU, memory, disk, network)

**Installation:**
```bash
# Download the latest release
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.8.2.linux-amd64.tar.gz
cd node_exporter-1.8.2.linux-amd64
./node_exporter
```

**Run as systemd service:**
```ini
# /etc/systemd/system/node-exporter.service
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable node-exporter
sudo systemctl start node-exporter
```

### 2. SMARTCTL Exporter (Optional but Recommended)
**Port:** 9633
**Purpose:** Disk health monitoring (SMART data)

**Installation:**
```bash
# Download the latest release
wget https://github.com/prometheus-community/smartctl_exporter/releases/download/v0.12.0/smartctl_exporter-0.12.0.linux-amd64.tar.gz
tar xvfz smartctl_exporter-0.12.0.linux-amd64.tar.gz
cd smartctl_exporter-0.12.0.linux-amd64
./smartctl_exporter
```

**Note:** Requires `smartctl` installed and root privileges to access disk SMART data.

**Run as systemd service:**
```ini
# /etc/systemd/system/smartctl-exporter.service
[Unit]
Description=Prometheus SMARTCTL Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/smartctl_exporter
User=root
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable smartctl-exporter
sudo systemctl start smartctl-exporter
```

## Verification

Once exporters are running on the NAS, verify they're accessible:

```bash
# Test from your local machine
curl http://nas.3226texas.com:9100/metrics  # Should return metrics
curl http://nas.3226texas.com:9633/metrics  # Should return disk metrics
```

## Firewall Configuration

Ensure ports 9100 and 9633 are accessible from your Kubernetes cluster nodes:

```bash
# Example for UFW
sudo ufw allow from 192.168.0.0/16 to any port 9100
sudo ufw allow from 192.168.0.0/16 to any port 9633
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
1. Check exporters are running: `systemctl status node-exporter smartctl-exporter`
2. Verify network connectivity from cluster: `kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://nas.3226texas.com:9100/metrics`
3. Check Prometheus targets: Visit https://prometheus.00o.sh/targets
4. Look for scrape errors in Prometheus logs

**High memory alert being silenced:**
There's a silence configured for `NodeMemoryHighUtilization` on the NAS at `nas.3226texas.com:9100`. If this is no longer needed, remove it from `kubernetes/apps/observability/silence-operator/silences/silences.yaml`.
