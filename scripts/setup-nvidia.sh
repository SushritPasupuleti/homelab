#!/usr/bin/env bash
set -euo pipefail

has_nvidia_gpu() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    return 0
  fi

  if [ -e /dev/nvidiactl ] || ls /dev/nvidia* >/dev/null 2>&1 2>/dev/null; then
    return 0
  fi

  return 1
}

if ! has_nvidia_gpu; then
  echo "No NVIDIA GPU detected on this host. Ollama will remain CPU-only unless you set OLLAMA_USE_NVIDIA=true manually."
  exit 0
fi

echo "NVIDIA GPU detected on this host."

if [ -f /etc/os-release ]; then
  . /etc/os-release
fi

case "${ID:-}" in
  ubuntu|debian)
    echo "Detected Debian/Ubuntu. Installing NVIDIA container toolkit..."
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=containerd
    sudo systemctl restart containerd
    echo "NVIDIA runtime configured for containerd."
    echo "Then install the Kubernetes device plugin:"
    echo "  kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.2/nvidia-device-plugin.yml"
    echo "Then re-run ./scripts/deploy.sh to enable GPU-backed Ollama."
    ;;
  nixos)
    echo "Detected NixOS. Add the following to your system configuration:"
    cat <<'EOF'
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
  };

  hardware.opengl.enable = true;
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.containerd.enable = true;
EOF
    echo "Then rebuild the system with: sudo nixos-rebuild switch"
    echo "After the rebuild, install the Kubernetes device plugin with:"
    echo "  kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.2/nvidia-device-plugin.yml"
    echo "Then run: OLLAMA_USE_NVIDIA=true ./scripts/deploy.sh"
    ;;
  *)
    echo "Unsupported distro for automatic NVIDIA toolkit setup. Follow the official NVIDIA container toolkit install steps for your system, then enable the NVIDIA device plugin in Kubernetes and re-run this script."
    ;;
 esac
