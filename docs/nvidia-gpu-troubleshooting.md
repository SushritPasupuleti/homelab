# NVIDIA GPU troubleshooting for this homelab

This note captures the practical host-side and Kubernetes-side fixes required to make Ollama schedule correctly on a GPU-enabled node.

## Symptom

The node has a real NVIDIA GPU, but the pod remains stuck in `Pending` with errors like:

```text
0/1 nodes are available: 1 Insufficient nvidia.com/gpu
```

Other common signals include:

```text
No valid resources detected
could not load NVML library: libnvidia-ml.so.1: cannot open shared object file
If this is a GPU node, did you configure the NVIDIA Container Toolkit?
```

## Root cause

The machine may have hardware and drivers installed, but Kubernetes still does not see the GPU because the runtime layer is not configured correctly. In practice, the root cause is often one of the following:

- the NVIDIA driver is installed but not active in the running system
- the container runtime is not configured for the NVIDIA runtime
- the device plugin was not refreshed after the runtime change
- the GPU is present but not visible to the cluster because the runtime or runtime class is missing

## Quick validation checklist

Before changing the cluster, confirm the host can see the GPU:

```bash
nvidia-smi
nvidia-container-cli -V
```

Then confirm Kubernetes sees it:

```bash
kubectl describe node <node-name> | grep -i nvidia
kubectl get nodes -o wide
```

You should see a resource such as:

```text
nvidia.com/gpu: 1
```

## Required host-side fix

### 1) Ensure the live NixOS config contains NVIDIA runtime settings

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

If the CLI is not on PATH, use the runtime binary directly:

```bash
sudo env PATH="/run/current-system/sw/bin:$PATH" nvidia-ctk runtime configure --runtime=containerd --set-as-default
```

Then restart the runtime and worker processes:

```bash
sudo systemctl restart containerd
sudo systemctl restart k3s
```

If your cluster is not managed by k3s, adapt the service name accordingly.

### 4) Refresh the Kubernetes NVIDIA device plugin

```bash
kubectl delete daemonset -n kube-system nvidia-device-plugin-daemonset --ignore-not-found
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.2/nvidia-device-plugin.yml
```

### 5) Verify the node advertises GPU resources

```bash
kubectl describe node <node-name> | grep -i nvidia
```

If the resource is still absent, the runtime remains the likely culprit rather than the pod spec.

## Re-deploy the app

Once the GPU is visible to Kubernetes:

```bash
cd /home/sushrit_lawliet/code/homelab
OLLAMA_USE_NVIDIA=true ./scripts/deploy.sh
```

Then validate:

```bash
kubectl get pods -n homelab | grep ollama
kubectl describe pod -n homelab -l app=ollama
```

## Best practices

- Keep the host runtime and the cluster runtime aligned.
- Prefer `nvidia-ctk` updates on the host OS over editing pod specs first.
- After runtime changes, always restart the runtime and refresh the GPU plugin.
- Avoid assuming the model app is broken when a pod is `Pending` because the Kubernetes node has no `nvidia.com/gpu` allocation.
- Confirm the node resource view before re-running a deployment.

## Notes

- The repository defaults are GPU-aware when the host is detected as NVIDIA-capable.
- On NixOS, the toolkit binary may exist in the store but not be active in PATH until after rebuild and a clean runtime configuration.
- The fix is usually host-side runtime configuration rather than a K8s YAML bug.
