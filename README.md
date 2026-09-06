# Homelab Kubernetes Stack

This repository sets up a Kubernetes-based homelab for running containerized services like Stock-EZ, along with a lightweight dashboard and network exposure for devices on the LAN.

## What is included

- Stock-EZ deployment as a Kubernetes workload
- Ollama as a cluster-local LLM service
- Persistent storage for SQLite databases and reports
- A configurable Homepage dashboard for service discovery, widgets, and mobile-friendly quick access
- Netdata for OS, container, and GPU visibility across the cluster and host
- Portainer for container management
- Home Assistant for central IoT/device management (including Bambu A1 integration path)
- A media stack for WDEX4100 libraries with Jellyfin, DLNA, and Plex-friendly access
- Ingress / LoadBalancer patterns for LAN access
- Shell scripts to deploy and update the stack

## How Stock-EZ maps to Kubernetes

From the upstream Stock-EZ project, the app is a Streamlit service that:

- runs on port 8501
- reads `config.yaml` from the working directory
- writes SQLite state under `data/`
- writes generated reports to `reports/`
- needs a reachable Ollama endpoint at `base_url`

In Kubernetes, the equivalent setup is:

- keep the app behind a `Service` and `Ingress`
- mount a PVC to `/app/data` and `/app/reports`
- mount a config file via `ConfigMap` to `/app/config.yaml`
- point the app to `http://ollama.homelab.svc.cluster.local:11434`

## Network access

The stack is designed to be reachable from your LAN through:

- `Ingress` hostnames such as `stock-ez.homelab.home.arpa`
- `NodePort` fallback endpoints when no external load balancer is configured
- `LoadBalancer` services when MetalLB or a cloud LB is available
- optional `hostAliases`, local DNS entries, or `/etc/hosts` overrides for `.local`/`home.arpa`

Important: `dashboard.homelab.home.arpa` and `portainer.homelab.home.arpa` will not resolve unless you either:

1. install and configure an ingress controller such as `ingress-nginx`, and
2. add a LAN DNS entry or `/etc/hosts` mapping for the node IP.

For a plain local lab, the easiest fix is to add an `/etc/hosts` entry on the machine that will browse the dashboard:

```bash
sudo sh -c 'echo "192.168.1.207 dashboard.homelab.home.arpa portainer.homelab.home.arpa stock-ez.homelab.home.arpa homeassistant.homelab.home.arpa open-webui.homelab.home.arpa ollama.homelab.home.arpa torrent.homelab.home.arpa files.homelab.home.arpa media.homelab.home.arpa plex.homelab.home.arpa" >> /etc/hosts'
```

This example maps the homelab hostnames directly to the ingress or MetalLB load balancer IP, which is the recommended LAN-only setup when you do not run a dedicated local DNS server.

A helper script is included to do this automatically:

```bash
sudo NODE_IP=192.168.1.207 ./scripts/update-hosts.sh
```

### NixOS-specific instructions

On NixOS, editing `/etc/hosts` is usually not the right path because the file is often read-only or managed by the system configuration. The safest option is to use `networking.extraHosts` in your Nix config.

Use the ingress IP, not the node IP. For example:

```nix
networking.extraHosts = ''
  192.168.1.207 dashboard.homelab.home.arpa portainer.homelab.home.arpa stock-ez.homelab.home.arpa homeassistant.homelab.home.arpa open-webui.homelab.home.arpa ollama.homelab.home.arpa media.homelab.home.arpa plex.homelab.home.arpa
'';
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

The repo includes a helper that writes a `homelab-hosts.nix` file for this pattern:

```bash
sudo NODE_IP=192.168.1.207 ./scripts/update-hosts.sh --nixos
```

This creates `/etc/nixos/homelab-hosts.nix`, and you should import it from `configuration.nix`:

```nix
imports = [ ./homelab-hosts.nix ];
```

If you prefer a proper LAN DNS setup instead of host entries, use a local DNS server, `systemd-resolved` domain entries, or MetalLB-backed ingress IPs. The direct MetalLB entry is the recommended approach for LAN-wide hostname resolution.

If you do not have an ingress controller, the fallback routes are:

- Dashboard: `http://<node-ip>:30080`
- Portainer: `http://<node-ip>:30900`

These NodePort values are intentionally fixed in the service manifests.

## Directory layout

- `k8s/namespace.yaml` – Kubernetes namespace
- `k8s/stock-ez/` – Stock-EZ manifests and config
- `k8s/ollama/` – local LLM service
- `k8s/dashboard/` – configurable Homepage dashboard UI
- `k8s/home-assistant/` – Home Assistant deployment
- `k8s/ingress/` – ingress rules for LAN access
- `k8s/portainer/` – container management UI
- `scripts/deploy.sh` – deploy the full stack
- `scripts/update.sh` – update images and roll out changes
- `scripts/delete-homelab.sh` – remove the entire homelab namespace
- `dashboard/` – static dashboard HTML/CSS web assets

## Python environment (pyenv + uv)

This repository pins the local Python version in `.python-version` and uses `uv` to manage the virtual environment.

```bash
# install the pinned interpreter
pyenv install 3.11.9
pyenv local 3.11.9

# create and activate the uv-managed virtual environment
uv venv --python 3.11.9 .venv
source .venv/bin/activate
uv pip install --python .venv/bin/python pyyaml
```

If `pyenv` is not installed yet, install it first and add it to your shell profile before running the commands above.

## Quick start

1. Bootstrap a Kubernetes cluster (for example k3s or k8s on your homelab node).
1. Ensure `kubectl` is configured to the cluster.
1. Review and edit `.env.example` if you want non-default values.
1. Run the deployment script:

```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```

1. Check resources:

```bash
kubectl get pods -n homelab
kubectl get svc -n homelab
kubectl get ingress -n homelab
```

## Service URLs

Once deployed, the expected services are:

- Stock-EZ: `http://stock-ez.homelab.home.arpa`
- Dashboard: `http://dashboard.homelab.home.arpa` or `http://<node-ip>:30080`
- Portainer: `http://portainer.homelab.home.arpa` or `http://<node-ip>:30900`
- Home Assistant: `http://homeassistant.homelab.home.arpa`
- Open WebUI: `http://open-webui.homelab.home.arpa` (chat UI for Ollama, model management, and API access)
- Netdata: `http://netdata.homelab.home.arpa` (host, container, and GPU metrics; use this for memory, CPU, network, and Ollama-related resource visibility)
- Ollama API: `http://ollama.homelab.home.arpa`
- Jellyfin: `http://media.homelab.home.arpa`
- Plex: `http://plex.homelab.home.arpa`

In environments with no local DNS, use the node IP and the service ports instead.

### Install the ingress controller first

If you see this error when creating an ingress:

```text
Error from server (InternalError): error when creating "STDIN": Internal error occurred: failed calling webhook "validate.nginx.ingress.kubernetes.io": failed to call webhook: Post "https://ingress-nginx-controller-admission.ingress-nginx.svc:443/networking/v1/ingresses?timeout=10s": no endpoints available for service "ingress-nginx-controller-admission"
```

then the `ingress-nginx` admission webhook is missing or not ready. Install the controller before applying the ingress manifests:

```bash
./scripts/install-ingress-nginx.sh
```

After it is ready, re-apply the ingress config:

```bash
kubectl apply -f k8s/ingress/ingress.yaml
```

### Alternative to /etc/hosts: MetalLB

If `/etc/hosts` is not practical, install MetalLB so your cluster can assign a real LAN IP to the Ingress. That makes the hostnames work without editing each client machine manually.

```bash
METALLB_IP_POOL=192.168.1.200-192.168.1.249 ./scripts/install-metallb.sh
```

The repo defaults this pool in `.env` and `.env.example` as `192.168.1.200-192.168.1.249`; change it to match your LAN range.

After MetalLB is installed, check the ingress IP:

```bash
kubectl get ingress -n homelab
kubectl get svc -n metallb-system
```

The Ingress should get an `ADDRESS` field from the configured pool. Then the hostname URLs should resolve on the LAN without /etc/hosts edits.

To verify DNS resolution locally:

```bash
getent hosts dashboard.homelab.home.arpa
curl -I http://dashboard.homelab.home.arpa
```

If the host does not resolve, use the NodePort fallback or add the entry to `/etc/hosts` manually.

## Deploy and update flow

### Deploy

```bash
./scripts/deploy.sh
```

The deploy script will:

- create the namespace
- apply the Stock-EZ config and workload
- deploy Ollama
- deploy Home Assistant, the dashboard, and Portainer
- apply the ingress rules

### Update

```bash
./scripts/update.sh
```

The update script refreshes container images and rolls out the new deployment state while keeping persistent volumes intact.

### Delete the whole namespace

```bash
./scripts/delete-homelab.sh
```

This removes the `homelab` namespace and all workloads, services, and config that were deployed into it.

## Monitoring recommendation

For this stack, the most practical recommendation is to keep Homepage and Open WebUI, and add Netdata as the observability layer. That gives you:

- Homepage as the landing page and quick access dashboard
- Open WebUI as the AI chat and model-management UI
- Netdata as the deeper monitoring view for CPU, RAM, disk, network, containers, and GPU visibility

This matches the pattern in the Awesome Homelab ecosystem: keep the app-specific tools, then add one dedicated monitoring stack instead of replacing the tools that already work well.

## NVIDIA GPU support for Ollama

The deploy script now auto-detects whether the host has an NVIDIA GPU. If it does, it enables GPU-aware Ollama settings automatically:

- toggles `OLLAMA_USE_NVIDIA=true` when `nvidia-smi` or `/dev/nvidia*` is present
- sets `NVIDIA_VISIBLE_DEVICES=all` and `NVIDIA_DRIVER_CAPABILITIES=compute,utility`
- adds the `nvidia` `RuntimeClass` and GPU resource requests for the Ollama pod
- leaves the deployment CPU-only when no GPU is detected

If you want to force the setting on a GPU box, set the environment value before running the script:

```bash
OLLAMA_USE_NVIDIA=true ./scripts/deploy.sh
```

To configure the host-side runtime, run the helper script:

```bash
./scripts/setup-nvidia.sh
```

On NixOS, the helper prints the hardware and containerd configuration you should add to your system config. Use this exact block:

```nix
hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = false;
  powerManagement.finegrained = false;
  open = false;
};

hardware.opengl.enable = true;
hardware.nvidia-container-toolkit.enable = true;
virtualisation.containerd.enable = true;
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

And install the Kubernetes device plugin:

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.2/nvidia-device-plugin.yml
```

For the full host-side troubleshooting notes, including the exact `nvidia-ctk`/containerd fixes and the symptoms seen on this NixOS setup, see [docs/nvidia-gpu-troubleshooting.md](docs/nvidia-gpu-troubleshooting.md).

## Recommended prerequisites

- Kubernetes cluster with storage class available (`longhorn`, `openebs`, or local-path)
- Ingress controller (for example `ingress-nginx` or Traefik)
- NVIDIA container runtime configured on the worker node if GPU acceleration is required
- LAN DNS entries or `/etc/hosts` overrides
- Adequate CPU/RAM for Ollama models, especially for large LLMs

## WDEX4100 media shares for Kodi, VLC, DLNA, and Plex

The WD EX4100 is a good fit as a read-only media source on the LAN. The most reliable pattern is:

1. Mount the WDEX4100 share to a stable host path such as `/mnt/wdex4100/media`.
2. Expose the share through a media server for browsing and metadata.
3. Keep a DLNA server available for Kodi/VLC/other DLNA clients.
4. Optionally run Plex for a more polished UI if you prefer a paid, feature-rich media experience.

Recommended setup:

- Jellyfin at `http://media.homelab.home.arpa` for a free media library UI
- MiniDLNA at the LAN for Kodi/VLC/DLNA autodiscovery
- Plex at `http://plex.homelab.home.arpa` for Plex clients if you want that experience

Mount the WDEX4100 share on the Kubernetes node:

```bash
sudo mkdir -p /mnt/wdex4100/media
sudo mount -t cifs //192.168.1.11/Volume_1/Media /mnt/wdex4100/media \
  -o username=admin,password=YOUR_PASSWORD,vers=3.0,uid=$(id -u),gid=$(id -g),iocharset=utf8
```

Or use the helper script:

```bash
PASSWORD='YOUR_PASSWORD' ./scripts/mount-wdex4100.sh
```

After the mount exists, deploy the media stack:

```bash
./scripts/deploy.sh
```

The manifests in `k8s/media/` assume the media root is available at `/mnt/wdex4100/media` and map it into the service containers from the WDEX4100 at `192.168.1.11`.

## Dashboard replacement

The original static HTML dashboard was intentionally replaced with Homepage, which is much easier to configure and extend without editing frontend code. You can update the dashboard directly in `k8s/dashboard/dashboard.yaml` by editing the `settings.yaml`, `services.yaml`, and `widgets.yaml` blocks.

The resulting dashboard is mobile friendly and supports quick links, service tiles, and widgets for a more complete homelab overview.

## Bambu A1 central management

There is no full browser-hosted clone of Bambu Studio itself, but there are two practical paths:

- Official path: Bambu Farm Manager + Bambu Handy (from Bambu Lab ecosystem)
- Self-hosted path: Home Assistant on your homelab with a Bambu integration for centralized monitoring/control in a mobile-friendly UI

This stack now includes Home Assistant so you can use the self-hosted path on your LAN.

## Notes

- Stock-EZ is not a public SaaS product; it is meant to run in a private homelab environment.
- The Homepage dashboard and Home Assistant UI are mobile friendly and configurable.
- This repository is intentionally generic so it can be adapted to your cluster, networking, and storage setup.

## Security note

These manifests are intended for internal networks only. Add authentication or VPN access before exposing services beyond your LAN.
