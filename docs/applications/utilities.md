# Utilities

## Forgejo

[Forgejo](https://forgejo.org/) is a self-hosted Git repository service:

- Located in `kubernetes/apps/utils/forgejo/`
- Kanidm SSO for authentication
- Forgejo Actions CI/CD via `forgejo-runner-system` namespace
- KEDA ScaledJobs for on-demand CI runners

## Homepage

[Homepage](https://gethomepage.dev/) provides a unified dashboard for all cluster services:

- Located in `kubernetes/apps/utils/homepage/`
- Central entry point for accessing all deployed services
- Status monitoring for services

!!! note
    When adding new applications, always add them to the Homepage configuration.

## Penpot

[Penpot](https://penpot.app/) is an open-source design and prototyping platform:

- Located in `kubernetes/apps/utils/penpot/`
- Multi-component: backend, frontend, exporter, Valkey cache
- PostgreSQL database via CloudNative-PG
- Persistent storage for assets via VolSync (20Gi)
- Exposed at `penpot.00o.sh`
- Kanidm SSO integration

### Dependencies

- CloudNative-PG postgres-cluster
- VolSync for persistent storage
- 1Password for secrets

## SMTP Relay

[Maddy](https://github.com/foxcpp/maddy) provides centralized SMTP relay:

- Located in `kubernetes/apps/utils/smtp-relay/`
- Accepts email on port 25 via LoadBalancer
- Relays through external SMTP provider
- Hostname: `smtp-relay.00o.sh`

### Usage

Applications send email to:

```
smtp-relay.utils.svc.cluster.local:25
```

### Security

- Non-root user (UID/GID 1000)
- Read-only root filesystem
- All capabilities dropped

## CI/CD Runners

### GitHub Actions (actions-runner-system)

Self-hosted GitHub Actions runners:

- Uses official Actions Runner Controller (ARC)
- Ephemeral runner pods
- Scales on webhook events
- Cluster access for image pulling and schema publishing

### Forgejo Runners (forgejo-runner-system)

Forgejo CI/CD runners:

- KEDA ScaledJobs for on-demand scaling
- Scales based on Forgejo webhook events
- Isolated execution environment

## Spegel

[Spegel](https://github.com/spegel-org/spegel) enables peer-to-peer container image sharing:

- Located in `kubernetes/apps/kube-system/spegel/`
- Nodes share images directly with each other
- Auto-enables with 2+ nodes
- Registry host port: 29999
- Reduces external registry pulls and bandwidth
