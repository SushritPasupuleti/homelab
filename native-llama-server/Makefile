.PHONY: install run help clean

PYTHON ?= python3
UV ?= uv
APP = llama_server.py
MODEL ?= /path/to/model.gguf
HOST ?= 0.0.0.0
PORT ?= 8001
GPU_LAYERS ?= 35
CTX_SIZE ?= 4096
BATCH_SIZE ?= 512
THREADS ?= 8
SERVER_BIN ?= $(shell command -v llama-server || echo llama-server)
EXTRA_ARGS ?=
ROOT_CACHE ?= $(abspath $(CURDIR)/../.cache/huggingface)
HF_HOME ?= $(ROOT_CACHE)
HUGGINGFACE_HUB_CACHE ?= $(ROOT_CACHE)
TRANSFORMERS_CACHE ?= $(ROOT_CACHE)
HF_DATASETS_CACHE ?= $(ROOT_CACHE)
HOMELAB_HF_CACHE ?= $(ROOT_CACHE)

export HF_HOME HUGGINGFACE_HUB_CACHE TRANSFORMERS_CACHE HF_DATASETS_CACHE HOMELAB_HF_CACHE

install:
	$(UV) sync
	@echo "Ensure llama-server is available in PATH or set LLAMA_SERVER_BIN."
	@command -v llama-server >/dev/null 2>&1 || echo "llama-server was not found in PATH; use the Nix shell in this folder or install it from the llama.cpp package."

run:
	mkdir -p "$(ROOT_CACHE)"
	$(UV) run python $(APP) \
		--model "$(MODEL)" \
		--host "$(HOST)" \
		--port "$(PORT)" \
		--server-bin "$(SERVER_BIN)" \
		--n-gpu-layers "$(GPU_LAYERS)" \
		--ctx-size "$(CTX_SIZE)" \
		--batch-size "$(BATCH_SIZE)" \
		--threads "$(THREADS)" \
		--extra-args "$(EXTRA_ARGS)"

help:
	$(UV) run python $(APP) --help

clean:
	find . -type d -name "__pycache__" -prune -exec rm -rf {} +
	# Keep the shared repo cache at ../.cache/huggingface intact for model reuse.
