#!/usr/bin/env python3
import argparse
import os
from pathlib import Path

from huggingface_hub import snapshot_download


def default_cache_dir() -> Path:
    return Path(__file__).resolve().parent / ".cache" / "huggingface"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download a model snapshot into the shared homelab Hugging Face cache.")
    parser.add_argument("model", help="Hugging Face repo id, such as unsloth/gemma-4-E2B-it")
    parser.add_argument(
        "--cache-dir",
        default=os.getenv("HOMELAB_HF_CACHE", str(default_cache_dir())),
        help="Directory to store the downloaded model snapshot. Defaults to the repo root .cache/huggingface.",
    )
    parser.add_argument(
        "--allow-pattern",
        default="*",
        help="Optional allow pattern for files to download (for example *.gguf or *.safetensors).",
    )
    parser.add_argument(
        "--revision",
        default=None,
        help="Optional commit or branch to download.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cache_dir = Path(args.cache_dir).resolve()
    cache_dir.mkdir(parents=True, exist_ok=True)

    print(f"Downloading {args.model} into {cache_dir}")
    snapshot = snapshot_download(
        repo_id=args.model,
        cache_dir=str(cache_dir),
        revision=args.revision,
        allow_patterns=[args.allow_pattern] if args.allow_pattern not in ("*", "") else None,
        local_dir_use_symlinks=False,
    )
    print(f"Downloaded snapshot: {snapshot}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
