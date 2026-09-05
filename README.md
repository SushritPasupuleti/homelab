# Homelab Kubernetes Stack

This repository sets up a Kubernetes-based homelab for running containerized services like Stock-EZ, along with a lightweight dashboard and network exposure for devices on the LAN.

## What is included

- Stock-EZ deployment as a Kubernetes workload
- Ollama as a cluster-local LLM service
- Persistent storage for SQLite databases and reports
- A responsive dashboard for service discovery and status
- Portainer for container management
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

- `Ingress` hostnames such as `stock-ez.homelab.local`
- `LoadBalancer` services for direct LAN IP access
- optional `hostAliases` or local DNS entries for `.local`/`home.arpa`

If your cluster has no Ingress controller, the `Service` objects still expose endpoints through the node IP and the configured node ports.

## Directory layout

- `k8s/namespace.yaml` – Kubernetes namespace
- `k8s/stock-ez/` – Stock-EZ manifests and config
- `k8s/ollama/` – local LLM service
- `k8s/dashboard/` – responsive dashboard UI
- `k8s/ingress/` – ingress rules for LAN access
- `k8s/portainer/` – container management UI
- `scripts/deploy.sh` – deploy the full stack
- `scripts/update.sh` – update images and roll out changes
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
2. Ensure `kubectl` is configured to the cluster.
3. Review and edit `.env.example` if you want non-default values.
4. Run the deployment script:

```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```

5. Check resources:

```bash
kubectl get pods -n homelab
kubectl get svc -n homelab
kubectl get ingress -n homelab
```

## Service URLs

Once deployed, the expected services are:

- Stock-EZ: `http://stock-ez.homelab.local`
- Dashboard: `http://dashboard.homelab.local`
- Portainer: `http://portainer.homelab.local`
- Ollama API: `http://ollama.homelab.local`

In environments with no local DNS, use the node IP and the service ports instead.

## Deploy and update flow

### Deploy

```bash
./scripts/deploy.sh
```

The deploy script will:

- create the namespace
- apply the Stock-EZ config and workload
- deploy Ollama
- deploy the dashboard and Portainer
- apply the ingress rules

### Update

```bash
./scripts/update.sh
```

The update script refreshes container images and rolls out the new deployment state while keeping persistent volumes intact.

## Recommended prerequisites

- Kubernetes cluster with storage class available (`longhorn`, `openebs`, or local-path)
- Ingress controller (for example `ingress-nginx` or Traefik)
- LAN DNS entries or `/etc/hosts` overrides
- Adequate CPU/RAM for Ollama models, especially for large LLMs

## Notes

- Stock-EZ is not a public SaaS product; it is meant to run in a private homelab environment.
- The dashboard is designed to be mobile friendly and responsive.
- This repository is intentionally generic so it can be adapted to your cluster, networking, and storage setup.

## Security note

These manifests are intended for internal networks only. Add authentication or VPN access before exposing services beyond your LAN.
