import argparse
import os
import shlex
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


def find_local_model_snapshot() -> str | None:
    cache_root = resolve_shared_cache_root()
    matches = sorted(cache_root.rglob("config.json"))
    preferred = [
        "gemma-4-E4B-it-qat",
        "gemma-4-E2B-it",
        "gemma-4",
        "gemma",
    ]
    for token in preferred:
        for match in matches:
            path = match.parent
            if token.lower() in path.name.lower() or token.lower() in str(path).lower():
                return str(path)
    if matches:
        return str(matches[0].parent)
    return None


DEFAULT_MODEL = os.getenv("VLLM_MODEL") or find_local_model_snapshot() or "unsloth/gemma-4-E2B-it"
DEFAULT_HOST = os.getenv("VLLM_HOST", "0.0.0.0")
DEFAULT_PORT = int(os.getenv("VLLM_PORT", "8000"))
DEFAULT_DTYPE = os.getenv("VLLM_DTYPE", "auto")
DEFAULT_GPU_MEMORY_UTILIZATION = float(os.getenv("VLLM_GPU_MEMORY_UTILIZATION", "0.50"))
DEFAULT_EXTRA_ARGS = os.getenv("VLLM_EXTRA_ARGS", "")


def configure_hf_cache(env: dict[str, str]) -> dict[str, str]:
    root = Path(__file__).resolve().parents[1]
    cache_root = Path(
        os.getenv("HOMELAB_HF_CACHE")
        or os.getenv("HF_HOME")
        or os.getenv("HUGGINGFACE_HUB_CACHE")
        or root / ".cache" / "huggingface"
    )
    cache_root.mkdir(parents=True, exist_ok=True)

    env["HOMELAB_HF_CACHE"] = str(cache_root)
    env["HF_HOME"] = str(cache_root)
    env["HUGGINGFACE_HUB_CACHE"] = str(cache_root)
    env["TRANSFORMERS_CACHE"] = str(cache_root)
    env["HF_DATASETS_CACHE"] = str(cache_root)
    return env

def resolve_target_device() -> str:
    forced = os.getenv("VLLM_TARGET_DEVICE")
    if forced:
        return forced.lower()

    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass

    return "cpu"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the native homelab vLLM server.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Model ID or local model path")
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bind host for the API server")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port for the API server")
    parser.add_argument("--dtype", default=DEFAULT_DTYPE, help="Model dtype, e.g. auto, bfloat16, float16")
    parser.add_argument(
        "--gpu-memory-utilization",
        type=float,
        default=DEFAULT_GPU_MEMORY_UTILIZATION,
        help="Fraction of GPU memory vLLM may use; default is 0.80 to leave headroom for the system and driver.",
    )
    parser.add_argument(
        "--extra-args",
        default=DEFAULT_EXTRA_ARGS,
        help="Extra arguments passed to vLLM as a single shell-style string",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args, extra = parser.parse_known_args()

    env = configure_hf_cache(os.environ.copy())
    os.environ.clear()
    os.environ.update(env)

    target_device = resolve_target_device()
    os.environ["VLLM_TARGET_DEVICE"] = target_device

    cmd = [
        sys.executable,
        "-m",
        "vllm.entrypoints.openai.api_server",
        "--host",
        args.host,
        "--port",
        str(args.port),
        "--model",
        args.model,
        "--dtype",
        args.dtype,
        "--gpu-memory-utilization",
        str(args.gpu_memory_utilization),
    ]

    if args.extra_args:
        extra = shlex.split(args.extra_args) + extra

    cmd.extend(extra)

    print("Starting native vLLM with:")
    print(f"  target device: {target_device}")
    print(f"  LD_LIBRARY_PATH={os.environ.get('LD_LIBRARY_PATH', '')}")
    print("  ", " ".join(cmd))

    try:
        return subprocess.call(cmd, env=os.environ.copy())
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
