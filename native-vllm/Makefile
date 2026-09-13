.PHONY: install run help clean run-model

PYTHON ?= python3
UV ?= uv
APP = native_vllm.py
MODEL ?= unsloth/gemma-4-E4B-it
HOST ?= 0.0.0.0
PORT ?= 8000
DTYPE ?= auto
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

run:
	mkdir -p "$(HF_HOME)"
	$(UV) run python $(APP) --model "$(MODEL)" --host "$(HOST)" --port "$(PORT)" --dtype "$(DTYPE)" -- $(EXTRA_ARGS)

run-model:
	mkdir -p "$(HF_HOME)"
	$(UV) run python $(APP) --model "$(MODEL)" --host "$(HOST)" --port "$(PORT)" --dtype "$(DTYPE)" -- $(EXTRA_ARGS)

help:
	$(UV) run python $(APP) --help

clean:
	$(RM) -rf .venv __pycache__
	find . -type d -name "__pycache__" -prune -exec rm -rf {} +
	# Keep the shared repo cache at ../.cache/huggingface intact for model reuse.
