# Native llama.cpp server

This is the standalone bare-metal llama.cpp service for the homelab stack. It mirrors the native vLLM pattern: a dedicated folder, a Nix CUDA shell, and a configurable launcher that lets you point at a different GGUF at any time.

## Purpose

- run llama.cpp outside k3s on the host
- keep Ollama as the default provider for the cluster
- expose a bare-metal OpenAI-compatible server when you want a GGUF-backed model
- run Unsloth-generated GGUFs with the llama.cpp server directly

This is intended to support the workflow described in the Unsloth integration docs: convert or export a GGUF model and then serve it locally with `llama-server`.

Important: `llama-server` does not accept a Hugging Face repo id like `unsloth/gemma-4-E2B-it` as a model target. It expects a local `.gguf` file path. The shared cache is searched automatically for a local GGUF, and if none is present the script exits with a clear error telling you to pass a concrete file path.

## Nix CUDA shell

From this folder:

```bash
nix-shell cuda-shell.nix
```

This shell exposes:

- the CUDA toolkit and NVIDIA libraries
- the `llama-server` binary from the Nix package
- `LLAMA_SERVER_BIN` pointing at the installed binary
- a repo-local Hugging Face cache
- fish as the default shell

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

## Quick start

```bash
cd native-llama-server
nix-shell cuda-shell.nix --run "python llama_server.py --model /path/to/model.gguf --host 0.0.0.0 --port 8001"
```

Or with a direct binary:

```bash
cd native-llama-server
LLAMA_SERVER_BIN=/path/to/llama-server python llama_server.py \
  --model /path/to/model.gguf \
  --host 0.0.0.0 \
  --port 8001 \
  --n-gpu-layers 35 \
  --ctx-size 4096 \
  --batch-size 512 \
  --threads 8
```

## Make targets

```bash
make help
make install
make run MODEL=/path/to/model.gguf HOST=0.0.0.0 PORT=8001 GPU_LAYERS=35
```

A more complete launch example:

```bash
make run MODEL=/models/unsloth-qwen3-8b.gguf HOST=0.0.0.0 PORT=8001 GPU_LAYERS=35 CTX_SIZE=8192 BATCH_SIZE=512 THREADS=8
```

## Environment variables

You can override these in the shell before starting the service:

```bash
export LLAMA_MODEL=/path/to/model.gguf
export LLAMA_HOST=0.0.0.0
export LLAMA_PORT=8001
export LLAMA_GPU_LAYERS=35
export LLAMA_CTX_SIZE=4096
export LLAMA_BATCH_SIZE=512
export LLAMA_THREADS=8
export LLAMA_EXTRA_ARGS="--jinja --log-disable"
```

Then start it without repeating the flags:

```bash
python llama_server.py
```

## Notes

- The wrapper accepts additional CLI arguments after `--`, which lets you pass model-specific or runtime-specific flags such as `--jinja`, `--cache-type-k`, or `--parallel`.
- The default port is `8001` to keep it separate from the vLLM service.
- The `n-gpu-layers` setting is intentionally configurable so you can tune the model for the current GPU and memory headroom.
- If you want a different model later, just swap the `--model` argument or set `LLAMA_MODEL` to a new GGUF path.

## Configs for Popular Models

Refer to [canirun.ai](https://www.canirun.ai/models/chat?status=featured) to understand which models work best on your hardware and use case.

### GPT-OSS-20B

```bash
llama-server --port 8001 --host 0.0.0.0 -hf unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M \                                       took 7m59s at 12:07:25 
         -ngl 54 \
         -c 8192 \
         -fa auto \
         -ctk q4_0 -ctv q4_0 \
         -b 1024 -ub 256 \
         -t 8 \
         --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0
```