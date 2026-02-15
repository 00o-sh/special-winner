# Cilium Networking

[Cilium](https://cilium.io/) 1.19.0 provides eBPF-based container networking, replacing the traditional kube-proxy.

## Features

- **eBPF dataplane** for high-performance packet processing
- **Network policies** with L3/L4/L7 filtering
- **Service mesh** capabilities (optional)
- **Hubble** for network observability
- **Load balancing** with direct server return

## Configuration

Cilium is deployed as a HelmRelease in `kube-system`:

```
kubernetes/apps/kube-system/cilium/
├── app/
│   ├── helmrelease.yaml
│   ├── ocirepository.yaml
│   └── kustomization.yaml
└── ks.yaml
```

## Checking Status

```sh
cilium status
cilium connectivity test    # Full connectivity test
```

## Hubble (Observability)

If enabled, Hubble provides network flow visibility:

```sh
hubble status
hubble observe --follow
```
