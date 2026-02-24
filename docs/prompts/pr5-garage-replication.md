# PR 5: Set up Garage cross-site replication

## Task

Configure Garage to replicate backup data across sites so that after failover, the standby cluster has access to all Volsync backup snapshots.

## Context

After PRs 3-4, each cluster has an independent Garage instance on local storage. Backups made on cluster 3226 are only on 3226's Garage. If 3226 fails, usny01's Garage has no data. This PR adds cross-site replication.

## Research needed first

Before implementing, research these questions:

1. **Garage multi-node across WAN**: Can Garage form a cluster across a site-to-site VPN? What are the latency requirements for its RPC protocol (port 3901)?

2. **Garage zone-aware replication**: Garage supports zone labels on nodes. With `replication_factor = 2` and two zones (one per site), Garage ensures one copy per zone. Is this production-ready?

3. **Alternative: rclone sync**: Instead of Garage clustering, would a CronJob running `rclone sync` between two independent Garage S3 instances be simpler and more reliable over WAN?

4. **Alternative: Kopia server-side replication**: Can Kopia itself be configured to replicate its repository to a second S3 endpoint?

## Approach A: Garage multi-site cluster

### Changes needed

1. **Garage configuration** — update `configuration.toml`:
   - Set `replication_factor = 2` (one copy per site)
   - Add zone configuration per node
   - Configure RPC endpoints to include the remote site's Garage

2. **Networking** — ensure port 3901 (Garage RPC) is routable over the site-to-site VPN between clusters

3. **Node discovery** — each Garage node needs to know the other site's node ID and address. This could be:
   - Static config via `bootstrap_peers`
   - DNS-based discovery

4. **Per-cluster Garage config** — the `configuration.toml` needs to differ per cluster (different `node_id`, different local address, same cluster). This may require making it a Jinja2 template or using Flux substitution.

## Approach B: rclone CronJob (simpler)

### Changes needed

1. **Create a CronJob** in `kubernetes/apps/volsync-system/garage/` that runs `rclone sync` between the local Garage S3 and the remote site's Garage S3
2. **Schedule**: every 6 hours or daily
3. **Credentials**: needs S3 access keys for both local and remote Garage instances
4. **Direction**: bidirectional sync or active→standby only

## Recommendation

Start with Approach B (rclone) as it's simpler, doesn't require Garage clustering, and works reliably over WAN with varying latency. Graduate to Approach A if the rclone approach proves too slow or introduces too much backup lag.

## Commit

Use semantic commit: `feat(volsync): add cross-site Garage backup replication`
