# Applications

All applications are deployed via Flux CD from manifests in `kubernetes/apps/`.

## Application Catalog

### Media Stack

| App | Description | Namespace |
|-----|-------------|-----------|
| [Plex](https://www.plex.tv/) | Media server | media |
| [Radarr](https://radarr.video/) | Movie collection manager | media |
| [Sonarr](https://sonarr.tv/) | TV series collection manager | media |
| [Prowlarr](https://prowlarr.com/) | Indexer manager | media |
| [Bazarr](https://www.bazarr.media/) | Subtitle management | media |
| [qBittorrent](https://www.qbittorrent.org/) | Torrent client | media |
| [Qui](https://github.com/autobrr/qui) | qBittorrent web UI | media |
| [Autobrr](https://autobrr.com/) | Torrent tracker automation | media |
| [Recyclarr](https://recyclarr.dev/) | Quality profile management | media |
| [Seerr](https://github.com/seerr-team/seerr) | Media request platform | media |
| [Tautulli](https://tautulli.com/) | Plex monitoring | media |
| [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) | Cloudflare bypass | media |
| [TheLounge](https://thelounge.chat/) | IRC client | media |

### VoIP & Telephony

| App | Description | Namespace |
|-----|-------------|-----------|
| [FreePBX](https://www.freepbx.org/) | Telephony platform (container + VMs) | voip |

### Networking & Testing

| App | Description | Namespace |
|-----|-------------|-----------|
| [LibreSpeed](https://librespeed.org/) | Multi-path speed test | default |

### Infrastructure & Utilities

| App | Description | Namespace |
|-----|-------------|-----------|
| [Forgejo](https://forgejo.org/) | Self-hosted Git | utils |
| [Homepage](https://gethomepage.dev/) | Cluster dashboard | utils |
| [n8n](https://n8n.io/) | Workflow automation | utils |
| [Penpot](https://penpot.app/) | Design platform | utils |
| [SMTP Relay](https://github.com/foxcpp/maddy) | Email relay (Maddy) | utils |
| [DBGate](https://dbgate.org/) | Database web UI | database |

### Virtualization

| App | Description | Namespace |
|-----|-------------|-----------|
| [KubeVirt](https://kubevirt.io/) | VM operator | kubevirt |
| [CDI](https://github.com/kubevirt/containerized-data-importer) | Disk importer | kubevirt |
| [KubeVirt Manager](https://kubevirt-manager.io/) | VM web UI | kubevirt |

### Observability

| App | Description | Namespace |
|-----|-------------|-----------|
| [Grafana](https://grafana.com/) | Metrics visualization | observability |
| [Prometheus](https://prometheus.io/) | Metrics collection | observability |
| [Victoria Logs](https://victoriametrics.com/) | Log aggregation | observability |
| [Gatus](https://github.com/TwiN/gatus) | Health monitoring | observability |
| [OpenCost](https://www.opencost.io/) | Cost analysis | observability |
| [Fluent Bit](https://fluentbit.io/) | Log forwarding | observability |
| [KEDA](https://keda.sh/) | Event-driven autoscaling | observability |

### CI/CD

| App | Description | Namespace |
|-----|-------------|-----------|
| Actions Runner Controller | GitHub Actions runners | actions-runner-system |
| Forgejo Runner | Forgejo CI/CD runners | forgejo-runner-system |

See the detailed pages for more on each category:

- [Media Stack](media.md)
- [FreePBX](freepbx.md)
- [Virtualization](virtualization.md)
- [Observability](observability.md)
- [Utilities](utilities.md)
- [LibreSpeed](librespeed.md)
