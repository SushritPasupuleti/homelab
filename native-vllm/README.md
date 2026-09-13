# Native vLLM

This is the standalone bare-metal vLLM project for the homelab stack. It is intentionally separate from the Kubernetes manifests so you can run it directly on the host, with or without an NVIDIA GPU.

## Purpose

- run vLLM outside k3s on the host
- keep Ollama as the default stack provider
- use a dedicated environment and project structure
- accept custom runtime arguments such as `--dtype auto`, `--max-model-len`, or `--gpu-memory-utilization`

## Quick start

```bash
cd native-vllm
make install
make run
```

## Hugging Face cache and model downloads

The project uses a writable, repo-local cache so model downloads do not try to write into the default home cache directory. This is important when the user profile does not have permission to create the Hugging Face cache tree.

For bash or zsh:

```bash
export HF_HOME="$PWD/.cache/huggingface"
export HUGGINGFACE_HUB_CACHE="$PWD/.cache/huggingface"
export TRANSFORMERS_CACHE="$PWD/.cache/huggingface"
export HF_DATASETS_CACHE="$PWD/.cache/huggingface"
mkdir -p "$HF_HOME"
```

For fish:

```fish
set -gx HF_HOME "$PWD/.cache/huggingface"
set -gx HUGGINGFACE_HUB_CACHE "$PWD/.cache/huggingface"
set -gx TRANSFORMERS_CACHE "$PWD/.cache/huggingface"
set -gx HF_DATASETS_CACHE "$PWD/.cache/huggingface"
mkdir -p "$HF_HOME"
```

The Nix CUDA shell also exports the same values automatically.

## Model and runtime overrides

You can override the model and runtime arguments with environment variables or CLI flags.

The default GPU memory utilization is intentionally lower than vLLM's aggressive default because this host's RTX 5060 Ti is a 16 GiB card and vLLM was trying to reserve about 92% of it, which leaves no room for the driver and runtime. The project defaults to `0.80` to keep startup stable.

```bash
cd native-vllm
VLLM_MODEL="unsloth/gemma-4-E4B-it" VLLM_PORT=8000 VLLM_HOST=0.0.0.0 VLLM_GPU_MEMORY_UTILIZATION=0.80 uv run python native_vllm.py --dtype auto
```

Or pass custom arguments after `--`:

```bash
cd native-vllm
uv run python native_vllm.py --model "unsloth/gemma-4-E4B-it" --dtype auto --gpu-memory-utilization 0.80 -- --max-model-len 16384
```

## Common commands

```bash
make help
make install
make run
make run-model MODEL="unsloth/gemma-4-E4B-it" HOST=0.0.0.0 PORT=8000 DTYPE=auto
make clean
```

## NixOS CUDA compatibility

On NixOS, Triton and vLLM may fail during startup with a missing `/sbin/ldconfig` path even though the system has a valid NVIDIA toolchain installed.

The actual binary is usually located here:

```bash
/run/current-system/sw/bin/ldconfig
```

but Triton calls the absolute path `/sbin/ldconfig` during startup. If the symlink is missing, the engine fails before serving requests.

Create the compatibility symlink once as root:

```bash
sudo mkdir -p /sbin
sudo ln -sf /run/current-system/sw/bin/ldconfig /sbin/ldconfig
```

The Nix CUDA shells in this project include a startup guard that warns if the symlink is missing and only creates it when run as root. This is intended to make the shell usable for local development without crashing on entry.

## Notes

- `--dtype auto` is the default behavior.
- The script uses `parse_known_args`, which means any trailing options after `--` are forwarded directly to vLLM.
- If no NVIDIA GPU is available, the server still starts in CPU fallback mode instead of failing immediately.
- This host-specific NixOS fix is required before the Triton backend can initialize the CUDA driver at startup.
