# NVIDIA GPU troubleshooting for this homelab

This note captures the host-side and Kubernetes-side fixes that were required to make the Ollama pod schedule correctly on a GPU-enabled node.

## Symptom

The node has a real NVIDIA GPU, but the pod remains stuck in `Pending` with:

```text
0/1 nodes are available: 1 Insufficient nvidia.com/gpu
```

The NVIDIA device plugin logs also report:

```text
No valid resources detected
could not load NVML library: libnvidia-ml.so.1: cannot open shared object file
If this is a GPU node, did you configure the NVIDIA Container Toolkit?
```

## Root cause

The hardware is present, but the runtime is not fully configured for Kubernetes:

- the NVIDIA driver is installed
- the NVIDIA container toolkit is present in the Nix store
- the CLI is not available on the active PATH in the expected way
- containerd was not reconfigured to use the NVIDIA runtime
- the Kubernetes device plugin had not yet been refreshed after the runtime change

## Required host-side fix

### 1) Ensure the live NixOS config contains the NVIDIA runtime settings

```nix
hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = false;
  powerManagement.finegrained = false;
  open = false;
  nvidiaSettings = true;
  package = config.boot.kernelPackages.nvidiaPackages.stable;
};

hardware.opengl.enable = true;
hardware.nvidia-container-toolkit.enable = true;
virtualisation.containerd.enable = true;
```

### 2) Rebuild the system

```bash
sudo nixos-rebuild switch
```

### 3) Configure the NVIDIA runtime for containerd

Use the installed toolkit binary directly if the CLI is not on PATH:

```bash
sudo env PATH="/run/current-system/sw/bin:$PATH" nvidia-ctk runtime configure --runtime=containerd --set-as-default
```

This version of the toolkit does not support `--restart-mode`; use explicit service restarts instead.

### 4) Restart the runtime and the cluster

```bash
sudo systemctl restart containerd
sudo systemctl restart k3s
```

If your service name differs, check:

```bash
systemctl status k3s
```

### 5) Refresh the Kubernetes NVIDIA device plugin

```bash
kubectl delete daemonset -n kube-system nvidia-device-plugin-daemonset --ignore-not-found
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.2/nvidia-device-plugin.yml
```

### 6) Verify Kubernetes sees the GPU

```bash
kubectl describe node nixy-zangetsu | grep -i nvidia
```

The node should list a resource like:

```text
nvidia.com/gpu: 1
```

## Re-run the app deployment

With the GPU visible to Kubernetes, redeploy the stack:

```bash
cd /home/sushrit_lawliet/code/homelab
OLLAMA_USE_NVIDIA=true ./scripts/deploy.sh
```

Then verify:

```bash
kubectl get pods -n homelab | grep ollama
kubectl describe pod -n homelab -l app=ollama
```

## Notes

- The repo defaults are intentionally GPU-aware when the host is detected as NVIDIA-capable.
- On NixOS, the `nvidia-ctk` binary may exist in the store but not be on PATH until the system rebuild is applied and the package is explicitly included in `environment.systemPackages`.
- The fix is host-side runtime configuration; the Kubernetes YAML itself was not the primary cause once the host runtime was correctly configured.
