import argparse
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def resolve_shared_cache_root() -> Path:
    root = Path(__file__).resolve().parents[1]
    cache_root = Path(
        os.getenv("HOMELAB_HF_CACHE")
        or os.getenv("HF_HOME")
        or os.getenv("HUGGINGFACE_HUB_CACHE")
        or root / ".cache" / "huggingface"
    )
    cache_root.mkdir(parents=True, exist_ok=True)
    if str(cache_root) != str(root / ".cache" / "huggingface"):
        return Path(root / ".cache" / "huggingface")
    return cache_root


def find_local_gguf_model(cache_root: Path | None = None) -> str | None:
    cache_root = cache_root or resolve_shared_cache_root()
    matches = sorted(cache_root.rglob("*.gguf"))
    if not matches:
        return None

    preferred = [
        "gemma-4-E4B-it-qat",
        "gemma-4-E2B-it",
        "llama",
        "qwen",
        "mistral",
    ]
    for token in preferred:
        for match in matches:
            if token.lower() in match.name.lower() or token.lower() in str(match).lower():
                return str(match)
    return str(matches[0])


def is_probably_hf_repo_id(value: str) -> bool:
    if not value or value.startswith("/") or value.startswith("."):
        return False
    if value.endswith(".gguf"):
        return False
    return "/" in value or "@" in value


DEFAULT_MODEL = (
    os.getenv("LLAMA_MODEL")
    or os.getenv("LLAMA_MODEL_PATH")
    or find_local_gguf_model(resolve_shared_cache_root())
    or "/path/to/model.gguf"
)
DEFAULT_HOST = os.getenv("LLAMA_HOST", "0.0.0.0")
DEFAULT_PORT = int(os.getenv("LLAMA_PORT", "8001"))
DEFAULT_GPU_LAYERS = int(os.getenv("LLAMA_GPU_LAYERS", "35"))
DEFAULT_CTX_SIZE = int(os.getenv("LLAMA_CTX_SIZE", "4096"))
DEFAULT_BATCH_SIZE = int(os.getenv("LLAMA_BATCH_SIZE", "512"))
DEFAULT_THREADS = int(os.getenv("LLAMA_THREADS", str(os.cpu_count() or 8)))
DEFAULT_EXTRA_ARGS = os.getenv("LLAMA_EXTRA_ARGS", "")


def configure_hf_cache(env: dict[str, str]) -> dict[str, str]:
    cache_root = resolve_shared_cache_root()
    env["HOMELAB_HF_CACHE"] = str(cache_root)
    env["HF_HOME"] = str(cache_root)
    env["HUGGINGFACE_HUB_CACHE"] = str(cache_root)
    env["TRANSFORMERS_CACHE"] = str(cache_root)
    env["HF_DATASETS_CACHE"] = str(cache_root)
    return env


DEFAULT_SERVER_BIN = os.getenv(
    "LLAMA_SERVER_BIN",
    shutil.which("llama-server") or "llama-server",
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the standalone llama.cpp server for the homelab stack.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Path to a GGUF model file")
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bind host for the API server")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port for the API server")
    parser.add_argument("--server-bin", default=DEFAULT_SERVER_BIN, help="Path to the llama-server binary")
    parser.add_argument("--n-gpu-layers", type=int, default=DEFAULT_GPU_LAYERS, help="Number of GPU layers to offload to CUDA")
    parser.add_argument("--ctx-size", type=int, default=DEFAULT_CTX_SIZE, help="Maximum context size")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE, help="Batch size")
    parser.add_argument("--threads", type=int, default=DEFAULT_THREADS, help="CPU worker threads")
    parser.add_argument("--extra-args", default=DEFAULT_EXTRA_ARGS, help="Extra arguments passed as a shell-style string")
    return parser


def main() -> int:
    parser = build_parser()
    args, extra = parser.parse_known_args()

    env = configure_hf_cache(os.environ.copy())
    os.environ.clear()
    os.environ.update(env)

    if not args.model:
        parser.error("A GGUF model path is required. Pass --model or set LLAMA_MODEL or LLAMA_MODEL_PATH.")

    model_path = Path(args.model)
    if is_probably_hf_repo_id(args.model):
        resolved = find_local_gguf_model(resolve_shared_cache_root())
        if resolved:
            args.model = resolved
            model_path = Path(args.model)
        else:
            parser.error(
                "No local GGUF model file was found in the shared cache. "
                "llama.cpp requires a real .gguf file path, not a Hugging Face repo ID. "
                "Use --model /path/to/model.gguf or set LLAMA_MODEL_PATH=/path/to/model.gguf."
            )

    if not model_path.exists():
        parser.error(
            f"Model file not found: '{args.model}'. "
            "llama.cpp requires a local GGUF path. Pass --model /path/to/model.gguf or set LLAMA_MODEL_PATH."
        )

    server_bin = args.server_bin
    if not os.path.exists(server_bin):
        parser.error(f"llama-server binary not found at '{server_bin}'. Use --server-bin or set LLAMA_SERVER_BIN.")

    cmd = [
        server_bin,
        "-m",
        args.model,
        "--host",
        args.host,
        "--port",
        str(args.port),
        "-ngl",
        str(args.n_gpu_layers),
        "-c",
        str(args.ctx_size),
        "-b",
        str(args.batch_size),
        "-t",
        str(args.threads),
    ]

    if args.extra_args:
        extra = shlex.split(args.extra_args) + extra

    cmd.extend(extra)

    print("Starting llama.cpp with:")
    print(f"  model: {args.model}")
    print(f"  binary: {server_bin}")
    print(f"  host: {args.host}:{args.port}")
    print(f"  gpu layers: {args.n_gpu_layers}")
    print(f"  ctx size: {args.ctx_size}")
    print(f"  batch size: {args.batch_size}")
    print(f"  threads: {args.threads}")
    print("  ", " ".join(cmd))

    try:
        return subprocess.call(cmd)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
