# TrueNAS Monitoring Setup

This observability stack expects certain exporters to be running on your TrueNAS (`nas.3226texas.com`) to collect metrics.

## Required Exporters on TrueNAS

### 1. Node Exporter (Required)
**Port:** 9100
**Purpose:** Basic system metrics (CPU, memory, disk, network)

#### Option A: TrueNAS SCALE (Recommended - Container-based)

**Via Docker/Kubernetes (built into SCALE):**

1. Go to **Apps** in TrueNAS SCALE UI
2. Search for "Prometheus Node Exporter" or use custom app
3. Or use the TrueCharts catalog if available

**Via CLI (TrueNAS SCALE):**
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

#### Option B: TrueNAS CORE (FreeBSD-based)

**Via Jail (Recommended for CORE):**
1. Create a jail for monitoring
2. Install node_exporter in the jail
3. Configure port forwarding

**Direct Installation (not recommended - survives updates poorly):**
```bash
# Download FreeBSD binary
fetch https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.freebsd-amd64.tar.gz
tar xvf node_exporter-1.8.2.freebsd-amd64.tar.gz
cp node_exporter-1.8.2.freebsd-amd64/node_exporter /usr/local/bin/

# Create rc.d script
cat > /usr/local/etc/rc.d/node_exporter <<'EOF'
#!/bin/sh
# PROVIDE: node_exporter
# REQUIRE: DAEMON
# KEYWORD: shutdown

. /etc/rc.subr

name=node_exporter
rcvar=node_exporter_enable
command="/usr/local/bin/node_exporter"

load_rc_config $name
: ${node_exporter_enable:=NO}

run_rc_command "$1"
EOF

chmod +x /usr/local/etc/rc.d/node_exporter

# Enable and start
sysrc node_exporter_enable=YES
service node_exporter start
```

### 2. SMARTCTL Exporter (Optional but Recommended)
**Port:** 9633
**Purpose:** Disk health monitoring (SMART data)

**TrueNAS already has `smartctl` installed!**

#### TrueNAS SCALE:
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

#### TrueNAS CORE:
```bash
# Download FreeBSD binary
fetch https://github.com/prometheus-community/smartctl_exporter/releases/download/v0.12.0/smartctl_exporter-0.12.0.freebsd-amd64.tar.gz
tar xvf smartctl_exporter-0.12.0.freebsd-amd64.tar.gz
cp smartctl_exporter-0.12.0.freebsd-amd64/smartctl_exporter /usr/local/bin/

# Create rc.d script
cat > /usr/local/etc/rc.d/smartctl_exporter <<'EOF'
#!/bin/sh
# PROVIDE: smartctl_exporter
# REQUIRE: DAEMON
# KEYWORD: shutdown

. /etc/rc.subr

name=smartctl_exporter
rcvar=smartctl_exporter_enable
command="/usr/local/bin/smartctl_exporter"

load_rc_config $name
: ${smartctl_exporter_enable:=NO}

run_rc_command "$1"
EOF

chmod +x /usr/local/etc/rc.d/smartctl_exporter

# Enable and start
sysrc smartctl_exporter_enable=YES
service smartctl_exporter start
```

## Verification

Once exporters are running on the NAS, verify they're accessible:

```bash
# Test from your local machine
curl http://nas.3226texas.com:9100/metrics  # Should return metrics
curl http://nas.3226texas.com:9633/metrics  # Should return disk metrics
```

## TrueNAS Firewall Configuration

### TrueNAS SCALE
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

### TrueNAS CORE
TrueNAS CORE doesn't typically have a firewall, but if you've configured one via `ipfw`:

```bash
# Add rules to /etc/rc.firewall or via TrueNAS Shell
ipfw add allow tcp from 192.168.0.0/16 to me 9100
ipfw add allow tcp from 192.168.0.0/16 to me 9633
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
   - TrueNAS SCALE: `systemctl status node-exporter smartctl-exporter`
   - TrueNAS CORE: `service node_exporter status && service smartctl_exporter status`

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
- TrueNAS SCALE: Services should auto-start. Check with `systemctl status`
- TrueNAS CORE: FreeBSD services may not persist through updates. Consider using a jail instead.

**High memory alert being silenced:**
There's a silence configured for `NodeMemoryHighUtilization` on the NAS at `nas.3226texas.com:9100`. TrueNAS typically uses a lot of memory for ZFS ARC cache, which is normal. If you want to remove this silence, edit `kubernetes/apps/observability/silence-operator/silences/silences.yaml`.

**After TrueNAS Update:**
TrueNAS updates may remove custom services. You may need to reinstall exporters after major updates. Consider:
- Using a jail (TrueNAS CORE)
- Using a custom app (TrueNAS SCALE)
- Creating a post-update script to reinstall exporters
