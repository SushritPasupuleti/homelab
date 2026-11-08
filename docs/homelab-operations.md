# Homelab operations guide

This guide covers the current LAN deployment: HTTPS ingress, service operations, the Homelab Control TUI, local image builds, Portfolio Puffin upstream sync, and local model management.

## Operating model

- Kubernetes workloads live in the `homelab` namespace. Ingress-nginx is installed in `ingress-nginx`.
- Browser traffic uses `*.homelab.home.arpa` and enters through the ingress on the node's LAN IP. The ingress redirects HTTP to HTTPS.
- The wildcard TLS certificate is signed by a private homelab CA. Clients must trust the CA certificate to avoid browser warnings.
- Pod-to-pod traffic uses Kubernetes Service DNS names. It is commonly HTTP inside the cluster; this does not change the HTTPS browser entry point.
- Several inference and media paths use host directories or `local-path` PVCs. Those paths are node-local and are not shared storage across nodes.

The `.home.arpa` suffix is intended for local networks. Public CAs do not issue publicly trusted certificates for it. A publicly trusted certificate requires a domain you control and a DNS-01 ACME setup with split DNS. See [RFC 8375](https://datatracker.ietf.org/doc/html/rfc8375).

## First deployment and updates

### Prerequisites

- A running k3s/Kubernetes cluster and working `kubectl` credentials.
- Stable LAN IP for the ingress node and LAN DNS rewrites pointing the service names to that IP.
- `openssl` for certificate setup.
- Python 3 for manifest rendering and utility scripts.
- Docker access for local Portfolio Puffin builds.
- Go 1.24 or later to run the Bubble Tea TUI.
- `sudo` access when importing local images into k3s containerd.

### Fresh cluster sequence

Install ingress, create the local certificate, install the CA on client devices, then deploy the stack:

```bash
HOST_IP=192.168.0.6 ./scripts/install-ingress-nginx.sh
./scripts/setup-homelab-tls.sh
./scripts/deploy.sh
```

Use the actual LAN IP in place of the example. `scripts/adguard-hosts.sh` prints host rewrites for AdGuard; copy them into the DNS service. `scripts/update-hosts.sh` can update local host entries on the machine where it is run.

Optional overrides in `.env.example` must be exported by the calling shell because `deploy.sh` and `update.sh` do not source `.env` automatically. For example:

```bash
cp .env.example .env
# Edit .env, then:
set -a; . ./.env; set +a
```

Generated and rotated credentials are stored separately in `.homelab-secrets.env`, which the deployment scripts do load automatically.

`scripts/deploy.sh` applies the complete stack and builds/imports Portfolio Puffin. `scripts/update.sh` re-renders and updates workloads and also rebuilds/imports Portfolio Puffin. Both require the TLS secret to exist before they apply the ingress. Use GPU settings as script arguments/environment values, for example:

```bash
GPU_SERVICE=none ./scripts/deploy.sh
GPU_SERVICE=ollama ./scripts/update.sh
OLLAMA_ENABLED=false UNSLOTH_ENABLED=true GPU_SERVICE=none ./scripts/deploy.sh
```

`GPU_SERVICE=none` disables GPU assignment; it does not disable the Ollama or Unsloth services. Use `--disable-ollama` or `--disable-unsloth` to scale those workloads off through the scripts.

## HTTPS, DNS, and client trust

The ingress uses the `homelab-wildcard-tls` Kubernetes secret in namespace `homelab`, containing a wildcard server certificate for `*.homelab.home.arpa`. `scripts/setup-homelab-tls.sh` creates a local root CA, signs a 397-day server certificate, verifies it, updates the TLS secret, and applies the ingress configuration. The root CA is valid for ten years.

Certificate files are stored in `.local/tls/`, which is gitignored:

- `homelab-root-ca.crt`: install this public certificate in each client's trusted root store.
- `homelab-root-ca.key`: private signing key. Keep it private and back it up securely; never copy it to client devices or commit it.
- `wildcard.homelab.home.arpa.crt` and `.key`: ingress server certificate and key.

On NixOS, add the root certificate to `security.pki.certificateFiles` and run `sudo nixos-rebuild switch`. On Debian or Ubuntu, install it with:

```bash
sudo install -m 0644 .local/tls/homelab-root-ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
sudo update-ca-certificates
```

Some browsers and mobile devices use a separate certificate store; import the root CA there as well. If the CA private key is lost and a new CA is generated, every client must trust the new root certificate.

Rerun `./scripts/setup-homelab-tls.sh` before the server certificate expires to issue and install a fresh leaf certificate from the same CA. DNS must resolve each service hostname to the ingress IP. To test without relying on DNS, use `curl --cacert .local/tls/homelab-root-ca.crt --resolve dashboard.homelab.home.arpa:443:<ingress-ip> https://dashboard.homelab.home.arpa/`.

Direct NodePort access bypasses ingress TLS. The ingress-nginx project announced retirement in March 2026 and no longer receives releases or security fixes; plan a migration to a maintained ingress or Gateway API implementation. See the [project retirement notice](https://kubernetes.github.io/ingress-nginx/).

## Homelab Control TUI

Run the interactive operator interface from the repository:

```bash
./scripts/homelab-tui.sh
./scripts/homelab-tui.sh --namespace homelab
```

The launcher sets `CGO_ENABLED=0` and uses Go modules. It reads Kubernetes Deployments and StatefulSets from the selected namespace and refreshes their ready/desired replica counts every eight seconds. It uses the active `kubectl` context and credentials. It does not manage DaemonSets or host systemd services such as native vLLM or llama.cpp.

| Key | Action |
| --- | --- |
| `↑` / `↓`, `j` / `k` | Select a workload |
| `r` | Delete its current pods gracefully; its controller recreates them |
| `d` | Roll the workload from its current Kubernetes spec and wait for rollout status |
| `s` | Save current replica count in an annotation, then scale to zero |
| `a` | Restore the saved replica count; defaults to one if no count was saved |
| `x` | Force-delete matching pods immediately; the controller recreates them |
| `D` | Run full `scripts/deploy.sh` with entered arguments/environment values |
| `u` | Run full `scripts/update.sh` with entered arguments/environment values |
| `P` | Reset the Unsloth Studio password |
| `M` | Pull/install an Ollama model in the running Ollama pod |
| `L` | List models installed in Ollama |
| `R` | Refresh workload list immediately |
| `q` | Quit |

The deploy/update prompt accepts script flags and environment assignments. It does not evaluate shell syntax or substitutions. Quote values containing spaces. For example, enter:

```text
GPU_SERVICE=none --disable-ollama
```

Argument prompts accept terminal paste, including multiline paste (line breaks become spaces), and horizontally scroll when the input is longer than the terminal.

The password reset invokes `scripts/reset-unsloth-password.sh`. It writes the generated password into the gitignored `.homelab-secrets.env` file and displays it in the TUI. The Unsloth pod must be running. Ollama model installation invokes `ollama pull <model>` inside the running Ollama pod, streams its progress into the TUI, and stores the model in the directory configured by the Ollama deployment. Model size and resource use depend on the selected tag.

The TUI's restart, redeploy, stop/start, and force-kill actions preserve PVCs. Do not confuse these with `scripts/redeploy-service.sh`: that legacy script deletes matching PVCs. `scripts/delete-homelab.sh` removes the entire namespace and all its application data.

## Portfolio Puffin: upstream sync, build, and deploy

Portfolio Puffin is vendored as a Git submodule at `services/portfolio-zero`, pointing to the upstream [`SushritPasupuleti/portfolio-zero`](https://github.com/SushritPasupuleti/portfolio-zero) repository. The homelab-specific Ollama integration patch is in `patches/portfolio-zero/`; the build script applies it to a temporary copy and leaves the upstream submodule clean.

Initialize or restore the pinned upstream revision after cloning this repository:

```bash
git submodule update --init --recursive
git submodule status
```

To advance the submodule to the upstream default branch, review the new code and commit the updated submodule pointer in the homelab repository:

```bash
git submodule update --remote services/portfolio-zero
git -C services/portfolio-zero log -1 --oneline
git diff --submodule
```

After review, stage `services/portfolio-zero` in the homelab repo and commit the new gitlink. Keep homelab-specific integration changes in `patches/portfolio-zero/`, not as uncommitted edits inside the upstream submodule.

Build the API and web images and import them into the Kubernetes node runtime:

```bash
sudo -v
./scripts/build-portfolio-puffin.sh
```

Docker builds `portfolio-puffin-api:local` and `portfolio-puffin-web:local`. For containerd-backed k3s, the script saves each Docker image and imports it with `sudo k3s ctr images import`; for a Docker-backed cluster it loads images into the configured Docker daemon. The script detects the node runtime. Use `PORTFOLIO_PUFFIN_IMPORT_IMAGES=false` to build without importing, or override tags with `PORTFOLIO_PUFFIN_API_IMAGE` and `PORTFOLIO_PUFFIN_WEB_IMAGE`.

Deploy Portfolio Puffin without reapplying the full stack:

```bash
./scripts/deploy-portfolio-puffin.sh
```

That script requires the TLS secret, builds/imports images, applies `k8s/portfolio/portfolio.yaml`, restarts both deployments, waits for readiness, and displays their status. The UI is exposed at `https://portfolio.homelab.home.arpa`. The API's SQLite data is mounted at `/app/data` on the 10 GiB `portfolio-puffin-data` PVC. The default model backend is the cluster-local Ollama service at `http://ollama.homelab.svc.cluster.local:11434`, with model `gemma4:e2b`; configure `PORTFOLIO_PUFFIN_LLM_BASE_URL` and `PORTFOLIO_PUFFIN_LLM_MODEL` when running the deployment script to override it. This is the current local Ollama integration; it does not configure an OpenAI cloud API key.

The Portfolio Puffin images use `imagePullPolicy: Never`. Kubernetes must have the exact tagged image loaded in its own runtime or the pod will report `ErrImageNeverPull`. The build script handles that runtime import. A Docker `build` alone is not sufficient for k3s containerd, and the system's `ctr` socket path may differ from generic containerd installations; use the script's `sudo k3s ctr images import` path rather than manually targeting `/run/k3s/containerd/containerd.sock`.

## Ollama and Unsloth model services

Ollama serves local models over its HTTP API and is the default local model backend. The deployment uses NVIDIA when selected and supported by both the host and Kubernetes; it falls back to CPU mode when GPU support is not available. The TUI `M` and `L` actions pull and list models. Open WebUI and Portfolio Puffin use the in-cluster Ollama Service DNS name.

Unsloth API and Studio run in one deployment and are designed to run without NVIDIA. `GPU_SERVICE=ollama` keeps the default GPU preference on Ollama and leaves Unsloth CPU-only; `GPU_SERVICE=none` sets both to CPU. The deployment has separate service ports for the API and Studio, and ingress hostnames `unsloth.homelab.home.arpa` and `unsloth-studio.homelab.home.arpa`. The model/data PVCs are `unsloth-data` and `model-store`.

Reset Studio credentials from the repository:

```bash
./scripts/reset-unsloth-password.sh
```

The TUI's `P` action does the same. The script needs a running `unsloth` Deployment and updates `UNSLOTH_STUDIO_USERNAME` and `UNSLOTH_STUDIO_PASSWORD` in `.homelab-secrets.env`.

## Persistent storage and destructive operations

- Portfolio Puffin: `portfolio-puffin-data`, 10 GiB, local-path, ReadWriteOnce.
- Ollama: `ollama-data`, 50 GiB, local-path, ReadWriteOnce for Ollama state; the configured model path is the host-mounted Hugging Face cache described above.
- Unsloth: `unsloth-data`, 100 GiB, and `model-store`, 200 GiB, local-path, ReadWriteOnce.
- Other services have their own local-path claims and/or hostPath mounts. Check the specific manifest before moving a workload to another node.

`local-path` volumes are node-local and do not support shared multi-node ReadWriteMany access. TUI restarts and rollouts keep claims. `scripts/redeploy-service.sh` deletes PVCs by design and can erase application state; `scripts/delete-homelab.sh` deletes the namespace and its claims. Inspect any future teardown command before running it against services with data.

## Troubleshooting checklist

Check pod events and claims before changing a deployment:

```bash
kubectl get pods,pvc,ingress -n homelab -o wide
kubectl describe pod -n homelab <pod-name>
kubectl get events -n homelab --sort-by=.lastTimestamp | tail -30
kubectl get secret -n homelab homelab-wildcard-tls
```

- `ErrImageNeverPull` on Portfolio Puffin: run `sudo -v && ./scripts/build-portfolio-puffin.sh` and verify the tag matches `k8s/portfolio/portfolio.yaml`.
- Pending Unsloth or Ollama pod: inspect `FailedScheduling` events, node memory requests, GPU capacity, and PVC binding. CPU mode removes GPU requirements but does not remove CPU, memory, image-pull, or storage requirements.
- Browser certificate warning: trust `.local/tls/homelab-root-ca.crt` on that client; do not install the private key.
- Hostname resolves but returns 404: compare the requested hostname with `kubectl get ingress -n homelab -o wide` and the host rule in `k8s/ingress/ingress.yaml`.
- HTTP succeeds only on a NodePort: that route bypasses ingress TLS; use the matching ingress hostname and ensure DNS targets the ingress IP.

For NVIDIA-specific runtime setup, see [NVIDIA GPU troubleshooting](nvidia-gpu-troubleshooting.md).
