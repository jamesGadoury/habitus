#!/usr/bin/env bash
# Build & install llama.cpp from source for CPU inference, then pull the
# default models used by the `llama` wrapper (shell/bin/llama).
# Usage: ./install-llama-cpp.sh            (no sudo needed — installs under ~/.local)
#   LLAMA_CPP_REF=b11193                    override the pinned release tag
#   LLAMA_CPP_FORCE=1                       rebuild even if the ref is already installed
#   LLAMA_CPP_NO_PULL=1                     skip downloading models
#
# Why source: GGML_NATIVE tunes the build for this CPU (AVX2/FMA/F16C, or
# AVX-512 where present), which the generic release zips do not.
#
# Steps:
#   1. clone/fetch ggml-org/llama.cpp into ~/.local/src/llama.cpp at LLAMA_CPP_REF
#   2. build only the tools we use (llama-cli, llama-completion, llama-bench),
#      statically linked so the binaries can be copied anywhere
#   3. copy them to ~/.local/opt/llama.cpp/bin, symlink into ~/.local/bin
#   4. `llama pull` the models listed in shell/llama/models.conf
#
# Idempotent: skips the build when ~/.local/opt/llama.cpp/REF matches LLAMA_CPP_REF.
# Build deps: git, cmake, a C++ compiler; ninja is used if present.

set -euo pipefail
IFS=$'\n\t'

LLAMA_CPP_REF="${LLAMA_CPP_REF:-b11193}"
REPO_URL="https://github.com/ggml-org/llama.cpp"
SRC_DIR="$HOME/.local/src/llama.cpp"
PREFIX="$HOME/.local/opt/llama.cpp"
BIN_LINK_DIR="$HOME/.local/bin"
TOOLS=(llama-cli llama-completion llama-bench)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/../shell/bin/llama"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_OK="$(tput setaf 2)" C_ERR="$(tput setaf 1)" C_RST="$(tput sgr0)"
else
  C_OK="" C_ERR="" C_RST=""
fi
say() { printf '%s==>%s %s\n' "$C_OK" "$C_RST" "$*"; }
die() {
  printf '%sError:%s %s\n' "$C_ERR" "$C_RST" "$*" >&2
  exit 1
}

for cmd in git cmake c++; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing build dependency: $cmd"
done

if [[ -z "${LLAMA_CPP_FORCE:-}" && -f "$PREFIX/REF" && "$(cat "$PREFIX/REF")" == "$LLAMA_CPP_REF" ]]; then
  say "llama.cpp $LLAMA_CPP_REF already installed in $PREFIX"
else
  if [[ -d "$SRC_DIR/.git" ]]; then
    say "Fetching $LLAMA_CPP_REF"
    git -C "$SRC_DIR" fetch --depth 1 origin tag "$LLAMA_CPP_REF"
  else
    say "Cloning $REPO_URL at $LLAMA_CPP_REF"
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --depth 1 --branch "$LLAMA_CPP_REF" "$REPO_URL" "$SRC_DIR"
  fi
  git -C "$SRC_DIR" -c advice.detachedHead=false checkout --force "$LLAMA_CPP_REF"

  generator=()
  command -v ninja >/dev/null 2>&1 && generator=(-G Ninja)

  say "Configuring (GGML_NATIVE=ON, static)"
  cmake -S "$SRC_DIR" -B "$SRC_DIR/build" "${generator[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF

  say "Building llama.cpp tools"
  cmake --build "$SRC_DIR/build" --config Release -j "$(nproc)" --target "${TOOLS[@]}"

  mkdir -p "$PREFIX/bin"
  for tool in "${TOOLS[@]}"; do
    install -m 0755 "$SRC_DIR/build/bin/$tool" "$PREFIX/bin/$tool"
  done
  printf '%s\n' "$LLAMA_CPP_REF" >"$PREFIX/REF"
  say "Installed to $PREFIX/bin"
fi

mkdir -p "$BIN_LINK_DIR"
for tool in "${TOOLS[@]}"; do
  link="$BIN_LINK_DIR/$tool"
  if [[ -e "$link" && ! -L "$link" ]]; then
    printf 'Warning: %s exists and is not a symlink, skipping\n' "$link" >&2
    continue
  fi
  ln -sfn "$PREFIX/bin/$tool" "$link"
done
say "Symlinked tools into $BIN_LINK_DIR"

if [[ -z "${LLAMA_CPP_NO_PULL:-}" ]]; then
  "$WRAPPER" pull default fast
fi
say "Done. Try: llama \"say hi in three words\""
