# Tuppr upgrade CRs — per-node split

This directory holds the Tuppr custom resources that drive node-level
upgrades. The Talos side is split **one file per node** on purpose;
the Kubernetes side stays a single cluster-wide CR.

## Why one file per node for Talos

Tuppr's `TalosUpgrade` CRD exposes a `nodeSelector` field. We use it
to scope each CR to exactly one node so the upgrade orchestration
can be controlled node-by-node from Git:

- `talosupgrade-singlenodemaster.yaml`
- `talosupgrade-node-01-pve.yaml`
- `talosupgrade-node-02-pve.yaml`

Each file has its own `# renovate:` marker on the `version` field.
Renovate opens **one PR per file** on a new Talos release (see the
`Talos per-node TalosUpgrade` rule in `.renovaterc.json5` — it gives
each file its own `groupName` so Renovate doesn't dedupe identical
`(depName, currentValue → newValue)` bumps into a single PR).

Workflow on a new Talos release:

1. Renovate opens 3 PRs (one per file). Each is mergeable on its own.
2. Pick the canary node and merge that PR first.
3. Flux applies the version bump; Tuppr's controller picks up the
   change on that one CR and drains/upgrades only that node.
4. Wait for the node to come back Ready and stay stable for a soak
   window of your choosing (≥30 min recommended after a major Talos
   bump).
5. Merge the next PR. Repeat.
6. If a canary node fails, the other two PRs stay open and the rest
   of the cluster stays on the old version. Recovery is one-node
   scope.

The single-CR / cluster-wide model that preceded this got us into
trouble on 2026-05-16: Tuppr's own controller was disrupted when its
node was drained mid-batch, leadership churned, the upgrade Job
errored, and the whole batch was abandoned with the cluster in a
half-upgraded state. The per-node-file split + Tuppr `replicaCount: 3`
together fix that failure mode.

## Why Kubernetes stays cluster-wide

`KubernetesUpgrade` doesn't expose `nodeSelector` (Tuppr CRD doesn't
support per-node Kubernetes versions), and Kubernetes version skew
rules make sustained per-node K8s divergence semantically iffy
anyway. So `kubernetesupgrade.yaml` is a single CR. With Tuppr's
3-replica HA in place, K8s rolling upgrades survive single-node
controller disruption the same way Talos ones now do.
