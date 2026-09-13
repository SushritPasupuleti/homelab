{ pkgs ? import <nixpkgs> {} }:

let
  cuda = pkgs.cudatoolkit;
  nv = pkgs.linuxPackages.nvidia_x11 or pkgs.linuxPackages.nvidiaPackages.stable;
  llama = pkgs.llama-cpp.override { cudaSupport = true; };
in
pkgs.mkShell {
  name = "llama-server-cuda-shell";

  buildInputs = with pkgs; [
    git
    curl
    python311
    uv
    cuda
    nv
    stdenv.cc
    fish
    llama
  ];

  shellHook = ''
    export CUDA_HOME="${cuda}"
    export CUDA_PATH="${cuda}"
    export PATH="${llama}/bin:${cuda}/bin:$PATH"
    export LLAMA_SERVER_BIN="${llama}/bin/llama-server"

    if [ -x /run/current-system/sw/bin/ldconfig ] && [ ! -e /sbin/ldconfig ]; then
      if [ "$(id -u)" -eq 0 ]; then
        mkdir -p /sbin
        cat > /sbin/ldconfig <<'SH'
#!/usr/bin/env bash
set -e
if [ "$#" -gt 0 ] && { [ "$1" = "-p" ] || [ "$1" = "--print-cache" ]; }; then
  exit 0
fi

echo "NixOS ldconfig shim: refusing to modify the immutable /nix/store linker cache." >&2
exit 0
SH
        chmod 755 /sbin/ldconfig
      else
        echo "Warning: NixOS ldconfig compatibility shim missing. Run as root once: sudo mkdir -p /sbin && sudo tee /sbin/ldconfig >/dev/null <<'SH' ..." >&2
      fi
    fi

    export HF_HOME="$PWD/.cache/huggingface"
    export HUGGINGFACE_HUB_CACHE="$PWD/.cache/huggingface"
    export TRANSFORMERS_CACHE="$PWD/.cache/huggingface"
    export HF_DATASETS_CACHE="$PWD/.cache/huggingface"
    mkdir -p "$HF_HOME"

    export LD_LIBRARY_PATH="${cuda}/lib:${nv}/lib:$LD_LIBRARY_PATH"
    export LIBRARY_PATH="${cuda}/lib:${nv}/lib:$LIBRARY_PATH"
    export C_INCLUDE_PATH="${cuda}/include:$C_INCLUDE_PATH"
    export CPLUS_INCLUDE_PATH="${cuda}/include:$CPLUS_INCLUDE_PATH"

    if [ -n "$IN_NIX_SHELL" ] && [ "$SHELL" != "${pkgs.fish}/bin/fish" ]; then
      exec ${pkgs.fish}/bin/fish
    fi
  '';
}
