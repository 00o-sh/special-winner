# 🏆 Special Winner - Kubernetes Home Cluster

> _GitHub's random name generator really outdid itself this time!_

A Kubernetes homelab cluster deployed with [Talos Linux](https://github.com/siderolabs/talos) and [Flux CD](https://github.com/fluxcd/flux2) for GitOps. This repository is based on the [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) and uses [makejinja](https://github.com/mirkolenz/makejinja) for configuration templating.

At its core, this project leverages [makejinja](https://github.com/mirkolenz/makejinja), a powerful tool for rendering templates. By reading configuration files—`cluster.yaml` and `nodes.yaml`—Makejinja generates the necessary configurations to deploy a Kubernetes cluster with the following features:

- Easy configuration through YAML files
- GitOps-based cluster management with Flux CD
- Automated secret encryption with SOPS
- Template-driven infrastructure as code
- Modular and extensible approach to cluster deployment

## ✨ Features

A Kubernetes cluster deployed with [Talos Linux](https://github.com/siderolabs/talos) and an opinionated implementation of [Flux](https://github.com/fluxcd/flux2) using [GitHub](https://github.com/) as the Git provider, [sops](https://github.com/getsops/sops) to manage secrets and [cloudflared](https://github.com/cloudflare/cloudflared) to access applications external to your local network.

### Core Infrastructure

**Operating System & Orchestration:**
- [Talos Linux](https://github.com/siderolabs/talos) 1.12.1 - Immutable Kubernetes OS
- [Kubernetes](https://kubernetes.io/) 1.34.0 - Container orchestration
- [Flux CD](https://github.com/fluxcd/flux2) 2.7.5 - GitOps continuous delivery

**Networking:**
- [Cilium](https://github.com/cilium/cilium) 1.19.0 - eBPF-based CNI
- [CoreDNS](https://coredns.io/) - Cluster DNS
- [Envoy Gateway](https://github.com/envoyproxy/gateway) - HTTP routing and ingress
- [k8s_gateway](https://github.com/ori-edge/k8s_gateway) - Internal DNS for cluster services
- [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared) - Secure external access
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni) - Multi-network support

**Security & Secrets:**
- [cert-manager](https://github.com/cert-manager/cert-manager) - TLS certificate automation
- [External Secrets Operator](https://external-secrets.io/) - External secret management
- [1Password](https://1password.com/) - Secret storage backend
- [SOPS](https://github.com/getsops/sops) 3.11.0 - Encrypted secrets in Git

**Storage:**
- [OpenEBS](https://github.com/openebs/openebs) - Cloud-native storage
- [VolSync](https://volsync.readthedocs.io/) - Volume replication and backup
- [Kopia](https://kopia.io/) - Backup repository
- [Garage](https://garagehq.deuxfleurs.fr/) - S3-compatible storage
- [CSI Driver NFS](https://github.com/kubernetes-csi/csi-driver-nfs) - NFS storage support
- [Snapshot Controller](https://github.com/kubernetes-csi/external-snapshotter) - Volume snapshots

**Observability:**
- [Grafana](https://grafana.com/) - Metrics visualization
- [Gatus](https://github.com/TwiN/gatus) - Health monitoring and uptime tracking
- [KEDA](https://keda.sh/) - Event-driven autoscaling
- [Kube Prometheus Stack](https://github.com/prometheus-operator/kube-prometheus) - Full monitoring stack (Prometheus, AlertManager)
- [Victoria Logs](https://victoriametrics.com/products/victorialogs/) - Log aggregation and search
- [Fluent Bit](https://fluentbit.io/) - Log forwarding and collection
- [Blackbox Exporter](https://github.com/prometheus/blackbox_exporter) - Endpoint monitoring
- [Kromgo](https://github.com/kashalls/kromgo) - Custom metrics publishing
- [Silence Operator](https://github.com/kbudde/silence-operator) - Alert silencing automation

**System Management:**
- [Reloader](https://github.com/stakater/Reloader) - Automatic pod restarts on config changes
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server) - Resource metrics
- [Tuppr](https://github.com/belak/tuppr) - Automated system upgrades

### Applications

**Media Stack:**
- [Plex](https://www.plex.tv/) - Media server
- [Radarr](https://radarr.video/) - Movie collection management
- [Sonarr](https://sonarr.tv/) - TV series collection management
- [Prowlarr](https://prowlarr.com/) - Indexer manager
- [Bazarr](https://www.bazarr.media/) - Subtitle management
- [qBittorrent](https://www.qbittorrent.org/) - Torrent client
- [Qui](https://github.com/autobrr/qui) - qBittorrent web UI
- [Autobrr](https://autobrr.com/) - Automation for torrent trackers
- [Recyclarr](https://recyclarr.dev/) - Quality profile management for *arr apps
- [Seerr](https://github.com/seerr-team/seerr) - Media request and discovery platform
- [Tautulli](https://tautulli.com/) - Plex monitoring and statistics
- [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) - Cloudflare bypass proxy
- [TheLounge](https://thelounge.chat/) - Self-hosted IRC client

**Infrastructure & Utilities:**
- [GitHub Actions Runner Controller](https://github.com/actions/actions-runner-controller) - Self-hosted GitHub Actions runners
- [SMTP Relay](https://github.com/foxcpp/maddy) - Outbound email relay using Maddy

**Additional DNS:**
- Cloudflare DNS integration
- UniFi DNS integration

### Development & Automation

- Development environment managed with [mise](https://mise.jdx.dev/)
- CI/CD workflows with [GitHub Actions](https://github.com/features/actions)
  - Self-hosted runners for cluster-aware operations
  - Automated container image pre-pulling to nodes
  - CRD schema extraction and publishing
- Automated dependency updates with [Renovate](https://www.mend.io/renovate)
- Flux manifest validation and diffs with [flux-local](https://github.com/allenporter/flux-local)
- Automated PR labeling (area and size labels)

**Note:** [Spegel](https://github.com/spegel-org/spegel) (container image mirror) automatically enables when running with 2+ nodes.

## 🚀 Let's Go!

There are **5 stages** outlined below for completing this project, make sure you follow the stages in order.

### Stage 1: Machine Preparation

> [!IMPORTANT]
> If you have **3 or more nodes** it is recommended to make 3 of them controller nodes for a highly available control plane. This project configures **all nodes** to be able to run workloads. **Worker nodes** are therefore **optional**.
>
> **Minimum system requirements**
> | Role    | Cores    | Memory        | System Disk               |
> |---------|----------|---------------|---------------------------|
> | Control/Worker | 4 | 16GB | 256GB SSD/NVMe |

1. Head over to the [Talos Linux Image Factory](https://factory.talos.dev) and follow the instructions. Be sure to only choose the **bare-minimum system extensions** as some might require additional configuration and prevent Talos from booting without it. Depending on your CPU start with the Intel/AMD system extensions (`i915`, `intel-ucode` & `mei` **or** `amdgpu` & `amd-ucode`), you can always add system extensions after Talos is installed and working.

2. This will eventually lead you to download a Talos Linux ISO (or for SBCs a RAW) image. Make sure to note the **schematic ID** you will need this later on.

3. Flash the Talos ISO or RAW image to a USB drive and boot from it on your nodes.

4. Verify with `nmap` that your nodes are available on the network. (Replace `192.168.1.0/24` with the network your nodes are on.)

    ```sh
    nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep 'Discovered'
    ```

### Stage 2: Local Workstation

1. Clone this repository and navigate to it:

    ```sh
    git clone https://github.com/00o-sh/special-winner.git
    cd special-winner
    ```

2. **Install** the [Mise CLI](https://mise.jdx.dev/getting-started.html#installing-mise-cli) on your workstation.

3. **Activate** Mise in your shell by following the [activation guide](https://mise.jdx.dev/getting-started.html#activate-mise).

4. Use `mise` to install the **required** CLI tools:

    ```sh
    mise trust
    pip install pipx
    mise install
    ```

   📍 _**Having trouble installing the tools?** Try unsetting the `GITHUB_TOKEN` env var and then run these commands again_

   📍 _**Having trouble compiling Python?** Try running `mise settings python.compile=0` and then run these commands again_

5. Logout of GitHub Container Registry (GHCR) as this may cause authorization problems when using the public registry:

    ```sh
    docker logout ghcr.io
    helm registry logout ghcr.io
    ```

### Stage 3: Cloudflare configuration

> [!WARNING]
> If any of the commands fail with `command not found` or `unknown command` it means `mise` is either not install or configured incorrectly.

1. Create a Cloudflare API token for use with cloudflared and external-dns by reviewing the official [documentation](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) and following the instructions below.

   - Click the blue `Use template` button for the `Edit zone DNS` template.
   - Name your token `kubernetes`
   - Under `Permissions`, click `+ Add More` and add permissions `Zone - DNS - Edit` and `Account - Cloudflare Tunnel - Read`
   - Limit the permissions to a specific account and/or zone resources and then click `Continue to Summary` and then `Create Token`.
   - **Save this token somewhere safe**, you will need it later on.

2. Create the Cloudflare Tunnel:

    ```sh
    cloudflared tunnel login
    cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes
    ```

### Stage 4: Cluster configuration

1. Generate the config files from the sample files:

    ```sh
    task init
    ```

2. Fill out `cluster.yaml` and `nodes.yaml` configuration files using the comments in those file as a guide.

3. Template out the kubernetes and talos configuration files, if any issues come up be sure to read the error and adjust your config files accordingly.

    ```sh
    task configure
    ```

4. Push your changes to git:

   📍 _**Verify** all the `./kubernetes/**/*.sops.*` files are **encrypted** with SOPS_

    ```sh
    git add -A
    git commit -m "chore: initial commit :rocket:"
    git push
    ```

> [!TIP]
> Using a **private repository**? Make sure to paste the public key from `github-deploy.key.pub` into the deploy keys section of your GitHub repository settings. This will make sure Flux has read/write access to your repository.

### Stage 5: Bootstrap Talos, Kubernetes, and Flux

> [!WARNING]
> It might take a while for the cluster to be setup (10+ minutes is normal). During which time you will see a variety of error messages like: "couldn't get current server API group list," "error: no matching resources found", etc. 'Ready' will remain "False" as no CNI is deployed yet. **This is a normal.** If this step gets interrupted, e.g. by pressing <kbd>Ctrl</kbd> + <kbd>C</kbd>, you likely will need to [reset the cluster](#-reset) before trying again

1. Install Talos:

    ```sh
    task bootstrap:talos
    ```

2. Push your changes to git:

    ```sh
    git add -A
    git commit -m "chore: add talhelper encrypted secret :lock:"
    git push
    ```

3. Install cilium, coredns, flux and sync the cluster to the repository state:

    ```sh
    task bootstrap:apps
    ```

    **Note:** Spegel will be automatically installed when you add a second node to the cluster.

4. Watch the rollout of your cluster happen:

    ```sh
    kubectl get pods --all-namespaces --watch
    ```

## 📣 Post installation

### ✅ Verifications

1. Check the status of Cilium:

    ```sh
    cilium status
    ```

2. Check the status of Flux and if the Flux resources are up-to-date and in a ready state:

   📍 _Run `task reconcile` to force Flux to sync your Git repository state_

    ```sh
    flux check
    flux get sources git flux-system
    flux get ks -A
    flux get hr -A
    ```

3. Check TCP connectivity to both the internal and external gateways:

   📍 _The variables are only placeholders, replace them with your actual values_

    ```sh
    nmap -Pn -n -p 443 ${cluster_gateway_addr} ${cloudflare_gateway_addr} -vv
    ```

4. Check you can resolve DNS for `echo`, this should resolve to `${cloudflare_gateway_addr}`:

   📍 _The variables are only placeholders, replace them with your actual values_

    ```sh
    dig @${cluster_dns_gateway_addr} echo.${cloudflare_domain}
    ```

5. Check the status of your wildcard `Certificate`:

    ```sh
    kubectl -n network describe certificates
    ```

### 🌐 Public DNS

> [!TIP]
> Use the `envoy-external` gateway on `HTTPRoutes` to make applications public to the internet. These are also accessible on your private network once you set up split DNS.

The `external-dns` application created in the `network` namespace will handle creating public DNS records. By default, `echo` and the `flux-webhook` are the only subdomains reachable from the public internet. In order to make additional applications public you must **set the correct gateway** like in the HelmRelease for `echo`.

### 🏠 Home DNS

> [!TIP]
> Use the `envoy-internal` gateway on `HTTPRoutes` to make applications private to your network. If you're having trouble with internal DNS resolution check out [this](https://github.com/onedr0p/cluster-template/discussions/719) GitHub discussion.

`k8s_gateway` will provide DNS resolution to external Kubernetes resources (i.e. points of entry to the cluster) from any device that uses your home DNS server. For this to work, your home DNS server must be configured to forward DNS queries for `${cloudflare_domain}` to `${cluster_dns_gateway_addr}` instead of the upstream DNS server(s) it normally uses. This is a form of **split DNS** (aka split-horizon DNS / conditional forwarding).

_... Nothing working? That is expected, this is DNS after all!_

### 🪝 Github Webhook

By default Flux will periodically check your git repository for changes. In-order to have Flux reconcile on `git push` you must configure Github to send `push` events to Flux.

1. Obtain the webhook path:

   📍 _Hook id and path should look like `/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123`_

    ```sh
    kubectl -n flux-system get receiver github-webhook --output=jsonpath='{.status.webhookPath}'
    ```

2. Piece together the full URL with the webhook path appended:

    ```text
    https://flux-webhook.${cloudflare_domain}/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

3. Navigate to the settings of your repository on Github, under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook URL and your token from `github-push-token.txt`, Content type: `application/json`, Events: Choose Just the push event, and save.

## 💥 Reset

> [!CAUTION]
> **Resetting** the cluster **multiple times in a short period of time** could lead to being **rate limited by DockerHub or Let's Encrypt**.

There might be a situation where you want to destroy your Kubernetes cluster. The following command will reset your nodes back to maintenance mode.

```sh
task talos:reset
```

## 🛠️ Talos and Kubernetes Maintenance

### ⚙️ Updating Talos node configuration

> [!TIP]
> Ensure you have updated `talconfig.yaml` and any patches with your updated configuration. In some cases you **not only need to apply the configuration but also upgrade talos** to apply new configuration.

```sh
# (Re)generate the Talos config
task talos:generate-config
# Apply the config to the node
task talos:apply-node IP=? MODE=?
# e.g. task talos:apply-node IP=10.10.10.10 MODE=auto
```

### ⬆️ Updating Talos and Kubernetes versions

> [!TIP]
> Ensure the `talosVersion` and `kubernetesVersion` in `talenv.yaml` are up-to-date with the version you wish to upgrade to.

```sh
# Upgrade node to a newer Talos version
task talos:upgrade-node IP=?
# e.g. task talos:upgrade-node IP=10.10.10.10
```

```sh
# Upgrade cluster to a newer Kubernetes version
task talos:upgrade-k8s
# e.g. task talos:upgrade-k8s
```

### ➕ Adding a node to your cluster

At some point you might want to expand your cluster to run more workloads and/or improve the reliability of your cluster. Keep in mind it is recommended to have an **odd number** of control plane nodes for quorum reasons.

You don't need to re-bootstrap the cluster to add new nodes. Follow these steps:

1. **Prepare the new node**: Review the [Stage 1: Machine Preparation](#stage-1-machine-preparation) section and boot your new node into maintenance mode.

2. **Get the node information**: While the node is in maintenance mode, retrieve the disk and MAC address information needed for configuration:

   ```sh
   talosctl get disks -n <ip> --insecure
   talosctl get links -n <ip> --insecure
   ```

3. **Update the configuration**: Read the documentation for [talhelper](https://budimanjojo.github.io/talhelper/latest/) and extend the `talconfig.yaml` file manually with the new node information (including the disk and MAC address from step 2).

4. **Generate and apply the configuration**:

   ```sh
   # Render your talosconfig based on the talconfig.yaml file
   task talos:generate-config

   # Apply the configuration to the node
   task talos:apply-node IP=?
   # e.g. task talos:apply-node IP=10.10.10.10
   ```

The node should join the cluster automatically and workloads will be scheduled once they report as ready.

## 🤖 Renovate

[Renovate](https://www.mend.io/renovate) is a tool that automates dependency management. It is designed to scan your repository around the clock and open PRs for out-of-date dependencies it finds. Common dependencies it can discover are Helm charts, container images, GitHub Actions and more! In most cases merging a PR will cause Flux to apply the update to your cluster.

To enable Renovate, click the 'Configure' button over at their [Github app page](https://github.com/apps/renovate) and select your repository. Renovate creates a "Dependency Dashboard" as an issue in your repository, giving an overview of the status of all updates. The dashboard has interactive checkboxes that let you do things like advance scheduling or reattempt update PRs you closed without merging.

The base Renovate configuration in your repository can be viewed at [.renovaterc.json5](.renovaterc.json5). By default it is scheduled to be active with PRs every weekend, but you can [change the schedule to anything you want](https://docs.renovatebot.com/presets-schedule), or remove it if you want Renovate to open PRs immediately.

## 🐛 Debugging

Below is a general guide on trying to debug an issue with an resource or application. For example, if a workload/resource is not showing up or a pod has started but in a `CrashLoopBackOff` or `Pending` state. These steps do not include a way to fix the problem as the problem could be one of many different things.

1. Check if the Flux resources are up-to-date and in a ready state:

   📍 _Run `task reconcile` to force Flux to sync your Git repository state_

    ```sh
    flux get sources git -A
    flux get ks -A
    flux get hr -A
    ```

2. Do you see the pod of the workload you are debugging:

    ```sh
    kubectl -n <namespace> get pods -o wide
    ```

3. Check the logs of the pod if its there:

    ```sh
    kubectl -n <namespace> logs <pod-name> -f
    ```

4. If a resource exists try to describe it to see what problems it might have:

    ```sh
    kubectl -n <namespace> describe <resource> <name>
    ```

5. Check the namespace events:

    ```sh
    kubectl -n <namespace> get events --sort-by='.metadata.creationTimestamp'
    ```

Resolving problems that you have could take some tweaking of your YAML manifests in order to get things working, other times it could be a external factor like permissions on a NFS server. If you are unable to figure out your problem see the support sections below.

## 🧹 Tidy up

Once your cluster is fully configured and you no longer need to run `task configure`, it's a good idea to clean up the repository by removing the [templates](./templates) directory and any files related to the templating process. This will help eliminate unnecessary clutter from the upstream template repository and resolve any "duplicate registry" warnings from Renovate.

1. Tidy up your repository:

    ```sh
    task template:tidy
    ```

2. Push your changes to git:

    ```sh
    git add -A
    git commit -m "chore: tidy up :broom:"
    git push
    ```

## ❔ What's next

There's a lot to absorb here, especially if you're new to these tools. Take some time to familiarize yourself with the tooling and understand how all the components interconnect. Dive into the documentation of the various tools included — they are a valuable resource. This shouldn't be a production environment yet, so embrace the freedom to experiment. Move fast, break things intentionally, and challenge yourself to fix them.

### What's Already Configured

This cluster already includes several advanced features beyond the base template:

- **✅ External Secrets Operator** - Integrated with 1Password for centralized secret management
- **✅ Storage Solutions** - OpenEBS, VolSync, CSI-driver-NFS, and snapshot controller
- **✅ Backup & Replication** - Kopia and Garage for S3-compatible backups
- **✅ Advanced DNS** - Cloudflare DNS and UniFi DNS webhooks configured
- **✅ Comprehensive Observability** - Full monitoring stack with Prometheus, Grafana, AlertManager, Victoria Logs, and more
- **✅ Complete Media Stack** - Plex, Radarr, Sonarr, Prowlarr, Bazarr, qBittorrent, and supporting tools
- **✅ GitHub Actions Infrastructure** - Self-hosted runners with cluster access for CI/CD
- **✅ SMTP Relay** - Centralized email relay for cluster applications
- **✅ Advanced Automation** - KEDA autoscaling, NFS-aware scaling, Discord alerts, automated image pre-pulling

### Additional Enhancements to Consider

**DNS Alternatives:**

While this cluster uses [k8s_gateway](https://github.com/ori-edge/k8s_gateway), you can explore additional DNS integrations:

- [Pi-hole](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/pihole.md) - Network-wide ad blocking
- [Adguard Home](https://github.com/muhlba91/external-dns-provider-adguard) - Privacy-focused DNS
- [Bind](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/rfc2136.md) - Traditional DNS server

**Storage Alternatives:**

If you want to explore alternatives to OpenEBS:

- [rook-ceph](https://github.com/rook/rook) - Distributed block, object, and file storage
- [longhorn](https://github.com/longhorn/longhorn) - Lightweight cloud-native storage
- [democratic-csi](https://github.com/democratic-csi/democratic-csi) - Storage integration for TrueNAS/FreeNAS
- [synology-csi](https://github.com/SynologyOpenSource/synology-csi) - Synology NAS integration

**Multi-Node Features:**

When you add a second node:
- **Spegel** will automatically enable for distributed image caching
- Consider enabling **BGP** for advanced load balancing with Cilium
- Explore **high availability** configurations for critical workloads

### Community Repositories

Community member [@whazor](https://github.com/whazor) created [Kubesearch](https://kubesearch.dev) to allow searching Flux HelmReleases across Github and Gitlab repositories with the `kubesearch` topic.

## 📋 TODO

### Phase 1: Build Everything on Test Cluster

**Foundation Services**
- [ ] CloudNativePG operator for managed PostgreSQL clusters
- [ ] Redis operator for managed Redis instances

**VM Infrastructure**
- [ ] Install KubeVirt + CDI for VM management
- [ ] Configure Multus NetworkAttachmentDefinitions for VM networking
- [ ] Export VMs from Proxmox nodes
- [ ] Import and test VMs in KubeVirt (single node, local/NFS storage)

**Cloud Service Mirroring**
- [ ] Nextcloud + OnlyOffice (Google Drive, Office 365, Calendar, Contacts mirror)
- [ ] Immich (Google Photos backup)
- [ ] Vaultwarden (Bitwarden/1Password supplementary instance)
- [ ] rclone CronJobs for automated cloud sync
- [ ] Linkding (bookmark backup)

**Security & Observability**
- [ ] Kyverno or OPA Gatekeeper for policy enforcement
- [ ] Network policies for namespace isolation
- [ ] Grafana Tempo for distributed tracing
- [ ] Falco or Trivy Operator for runtime security

**Additional Services**
- [ ] Forgejo (self-hosted Git platform)
- [ ] Home Assistant + IoT stack (if needed)
- [ ] Authelia or Authentik for SSO

### Phase 2: Test Multi-Node Features

**Add Second Node (VM)**
- [ ] Create Talos VM as second cluster node
- [ ] Verify Spegel auto-enables (distributed image caching)
- [ ] Deploy Longhorn for distributed block storage

**VM Testing**
- [ ] Migrate test VMs to Longhorn storage
- [ ] Test VM live migration between nodes
- [ ] Test VM startup on different nodes
- [ ] Verify VM networking across nodes

**High Availability Testing**
- [ ] Deploy critical workloads with replicas across nodes
- [ ] Test pod rescheduling (kill a node, watch pods move)
- [ ] Test volsync backup/restore
- [ ] Configure pod disruption budgets
- [ ] Simulate node failure scenarios
- [ ] Verify all services survive node loss

**Final Validation**
- [ ] All apps running and accessible
- [ ] All VMs running in KubeVirt
- [ ] HA confirmed working
- [ ] Backups tested and working
- [ ] Everything defined in Git (no manual kubectl resources)
- [ ] Document any manual steps still needed

### Phase 3: Nuclear Option 💥

- [ ] Take final backups of anything not in Git/volsync
- [ ] Nuke entire test cluster (`task talos:reset`)
- [ ] Add 2 Proxmox nodes as cluster hardware
- [ ] Re-bootstrap 3-node production cluster (`task bootstrap:talos` + `task bootstrap:apps`)
- [ ] Watch Flux restore everything magically ✨
- [ ] Watch volsync restore all data
- [ ] Verify all apps come back healthy
- [ ] Verify all VMs come back healthy
- [ ] Run same HA tests from Phase 2
- [ ] Celebrate successful GitOps validation 🎉

### Phase 4: Production Hardening

**Performance & Optimization**
- [ ] Review resource limits and requests
- [ ] Optimize Longhorn replica settings for 3 nodes
- [ ] Configure proper backup schedules
- [ ] Set up monitoring alerts

**Documentation**
- [ ] Document the disaster recovery procedure
- [ ] Document VM management workflow
- [ ] Update CLAUDE.md with lessons learned

## 🙋 Support

### Community Resources

- **Upstream Template**: [onedr0p/cluster-template discussions](https://github.com/onedr0p/cluster-template/discussions)
- **Discord**: [Home Operations](https://discord.gg/home-operations) - Join the `#cluster-template` channel
- **Documentation**: Check [CLAUDE.md](./CLAUDE.md) for detailed AI assistant guidance

### Acknowledgments

This repository is based on [@onedr0p](https://github.com/onedr0p)'s excellent [cluster-template](https://github.com/onedr0p/cluster-template). Many thanks to the Home Operations community for their continuous improvements and support.

## 🙌 Related Projects

If this repo is too hot to handle or too cold to hold check out these following projects.

- [ajaykumar4/cluster-template](https://github.com/ajaykumar4/cluster-template) - _A template for deploying a Talos Kubernetes cluster including Argo for GitOps_
- [khuedoan/homelab](https://github.com/khuedoan/homelab) - _Fully automated homelab from empty disk to running services with a single command._
- [mitchross/k3s-argocd-starter](https://github.com/mitchross/k3s-argocd-starter) - starter kit for k3s, argocd
- [ricsanfre/pi-cluster](https://github.com/ricsanfre/pi-cluster) - _Pi Kubernetes Cluster. Homelab kubernetes cluster automated with Ansible and FluxCD_
- [techno-tim/k3s-ansible](https://github.com/techno-tim/k3s-ansible) - _The easiest way to bootstrap a self-hosted High Availability Kubernetes cluster. A fully automated HA k3s etcd install with kube-vip, MetalLB, and more. Build. Destroy. Repeat._

## 📊 Repository Stats

**Deployed Components:** 50+ applications across 13 namespaces
**Template Source:** [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)
**Infrastructure:** GitOps with Flux CD + Talos Linux
**Last Updated:** 2026-01-21

---

<div align="center">

_"In a world of randomly generated repository names, this one turned out to be a winner."_ 🏆

Built with ☕ and ⚡ by the Home Operations community

</div>
