# Getting Started

This guide walks through deploying the cluster from bare metal to a fully operational GitOps-managed Kubernetes environment.

## Overview

There are **5 stages** to complete:

1. **[Prerequisites](prerequisites.md)** -- Prepare machines and install tools
2. **[Configuration](configuration.md)** -- Configure cluster and node settings
3. **[Bootstrap](bootstrap.md)** -- Deploy Talos, Kubernetes, and Flux
4. **[Post-Install](post-install.md)** -- Verify and configure DNS, webhooks

## Minimum Requirements

| Role | Cores | Memory | System Disk |
|------|-------|--------|-------------|
| Control/Worker | 4 | 16GB | 256GB SSD/NVMe |

!!! tip
    With **3 or more nodes**, make 3 of them controller nodes for a highly available control plane. All nodes are configured to run workloads -- worker nodes are optional.

## Time Estimate

- Stage 1-2 (prep + config): Variable depending on hardware
- Stage 3 (bootstrap): 10-15 minutes (errors during bootstrap are normal)
- Stage 4 (verification): 5-10 minutes
