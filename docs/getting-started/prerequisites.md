# Prerequisites

## Machine Preparation

1. Go to the [Talos Linux Image Factory](https://factory.talos.dev) and build an image:
    - Choose **bare-minimum system extensions** only
    - Start with CPU-specific extensions: `i915`, `intel-ucode`, `mei` (Intel) or `amdgpu`, `amd-ucode` (AMD)
    - Note the **schematic ID** -- you'll need it later

2. Flash the Talos ISO/RAW image to USB and boot your nodes

3. Verify nodes are reachable:

    ```sh
    nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep 'Discovered'
    ```

## Local Workstation

1. Clone the repository:

    ```sh
    git clone https://github.com/00o-sh/special-winner.git
    cd special-winner
    ```

2. Install [Mise CLI](https://mise.jdx.dev/getting-started.html#installing-mise-cli) and [activate](https://mise.jdx.dev/getting-started.html#activate-mise) it in your shell

3. Install required tools:

    ```sh
    mise trust
    pip install pipx
    mise install
    ```

    !!! note
        Having trouble? Try `unset GITHUB_TOKEN` and run again. For Python compilation issues: `mise settings python.compile=0`

4. Logout of GHCR to avoid auth issues:

    ```sh
    docker logout ghcr.io
    helm registry logout ghcr.io
    ```

## Cloudflare Setup

1. Create a Cloudflare API token with:
    - `Zone - DNS - Edit` permission
    - `Account - Cloudflare Tunnel - Read` permission
    - Name it `kubernetes`

2. Create the tunnel:

    ```sh
    cloudflared tunnel login
    cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes
    ```

## Tool Versions

All tools are managed via `.mise.toml`:

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.14.3 | Template rendering |
| kubectl | 1.34.0 | Kubernetes CLI |
| Helm | 4.1.1 | Chart management |
| Flux | 2.7.5 | GitOps CLI |
| Talos CLI | 1.12.4 | Talos management |
| Cilium CLI | 0.19.1 | Network management |
| SOPS | 3.12.1 | Secret encryption |
| Age | 1.3.1 | Encryption backend |
| virtctl | 1.7.0 | VM management |
| k9s | 0.50.18 | Kubernetes TUI |
