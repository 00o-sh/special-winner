# garage-ha — 3-zone HA Garage cluster

3-replica Garage S3 cluster with `replication_factor=3`, one zone per node (`z1`, `z2`, `z3`). Replaces the single-instance `garage` deployment in the same namespace.

## Layout bootstrap (one-time)

Garage's cluster layout is **not** managed in this repo, for two reasons:

1. `garage layout apply --version N` is strictly non-idempotent (`N` must be exactly `previous + 1`), so a Flux-applied Job that runs on every reconcile would fail after the first success.
2. `dxflrs/garage` and `ghcr.io/00o-sh/kubectl-distroless` are both distroless — no shell. A Job that does *wait + parse node IDs + assign + apply* requires either a shell-having image (avoided here) or hardcoded node IDs that go stale on disk loss.

The layout is therefore set up manually once per cluster lifetime. The procedure below is idempotent enough in practice (the assigns are no-ops if the role already matches; the apply fails harmlessly if the version is already applied).

### Procedure

```bash
# 1. Wait for the StatefulSet to be Ready (3 pods, each with a registered GarageNode CRD)
kubectl -n volsync-system rollout status statefulset/garage-ha
kubectl -n volsync-system exec garage-ha-0 -c app -- /garage status

# 2. Capture each node's auto-generated ID (16 hex chars in the first column)
status=$(kubectl -n volsync-system exec garage-ha-0 -c app -- /garage status)
ID0=$(echo "$status" | awk '/garage-ha-0/{print $1; exit}')
ID1=$(echo "$status" | awk '/garage-ha-1/{print $1; exit}')
ID2=$(echo "$status" | awk '/garage-ha-2/{print $1; exit}')

# 3. Stage and apply the 3-zone layout (100 GiB capacity each, matches the PV size)
g() { kubectl -n volsync-system exec garage-ha-0 -c app -- /garage "$@"; }
g layout assign --zone z1 --capacity 100000000000 "$ID0"
g layout assign --zone z2 --capacity 100000000000 "$ID1"
g layout assign --zone z3 --capacity 100000000000 "$ID2"
g layout apply --version 1

# 4. Verify
g status
```

Expected end state:

```
ID                Hostname     Address            Zone  Capacity
752a742513e3e55e  garage-ha-2  …                  z3    93.1 GiB
c5a94b43fbce2da9  garage-ha-1  …                  z2    93.1 GiB
e2798360deb3247b  garage-ha-0  …                  z1    93.1 GiB
```

### DR rebuild

If a node's PV is wiped (disk loss / cluster rebuild), Garage generates a new node ID for the replacement instance on first start. Re-run the procedure above with the fresh IDs from `garage status`. The cluster layout in `metadata_dir` persists across pod restarts, so this only happens on actual disk loss.

## Bucket data migration (one-time, one-off)

When migrating from the old single-instance `garage` to this HA cluster, copy bucket data with `rclone sync` against both S3 endpoints — see the migration runbook in [docs/operations](../../../docs/operations) (if present) or run as a scratch `kubectl run rclone ...` Job at the cutover. Not committed to the repo: it's a one-shot migration step, not a recurring concern.
