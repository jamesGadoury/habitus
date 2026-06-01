#!/usr/bin/env bash
# Build & install Ghostty terminal from source on Ubuntu, with desktop integration.
# Usage: sudo ./install-ghostty.sh
#   GHOSTTY_VERSION=1.3.1  ZIG_VERSION=0.15.2   override defaults
#
# Why source: at time of writing Ghostty isn't packaged in Ubuntu 24.04;
# Ubuntu 26.04 ships it but 24.04 does not. Source build is the
# upstream-recommended path on 24.04.
#
# Steps:
#   1. apt-install build deps + minisign + patchelf
#   2. download & verify (minisign) Zig and Ghostty tarballs
#   3. build with -Doptimize=ReleaseFast and -fno-sys=gtk4-layer-shell
#      (Ubuntu 24.04 doesn't package libgtk4-layer-shell-dev, so Ghostty
#      compiles it from source as part of the build)
#   4. patchelf the binary's RPATH to $ORIGIN/../lib so it finds its
#      bundled libgtk4-layer-shell.so without LD_LIBRARY_PATH or
#      system-wide ld.so.conf changes
#   5. refresh user desktop database + icon cache
#   6. register as x-terminal-emulator via update-alternatives
#
# Idempotent: skips Zig if already at the requested version, skips the
# Ghostty build if the installed binary matches GHOSTTY_VERSION.

set -euo pipefail
IFS=$'\n\t'

[[ $EUID -ne 0 ]] && exec sudo -E "$0" "$@"

GHOSTTY_VERSION="${GHOSTTY_VERSION:-1.3.1}"
ZIG_VERSION="${ZIG_VERSION:-0.15.2}"

# Project signing keys (verify against upstream docs before bumping)
GHOSTTY_PUBKEY="RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV"
ZIG_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

target_user="${SUDO_USER:-$USER}"
target_home=$(getent passwd "$target_user" | cut -d: -f6)
[[ -d $target_home ]] || {
  printf 'Error: home %s not found for %s\n' "$target_home" "$target_user" >&2
  exit 1
}

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  c_info=$(tput setaf 6)
  c_ok=$(tput setaf 2)
  c_off=$(tput sgr0)
else
  c_info=''
  c_ok=''
  c_off=''
fi

log() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok() { printf '%s==>%s %s\n' "$c_ok" "$c_off" "$*"; }

log "Installing system build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  libgtk-4-dev \
  libadwaita-1-dev \
  gettext \
  libxml2-utils \
  blueprint-compiler \
  pkg-config \
  minisign \
  patchelf \
  curl \
  xz-utils \
  ca-certificates \
  desktop-file-utils \
  hicolor-icon-theme \
  libgtk-3-bin \
  >/dev/null

log "Building & installing Ghostty $GHOSTTY_VERSION as $target_user"

# Drop privileges for the per-user phase. Heredoc is single-quoted so
# expansion happens in the child shell — variables are passed via env.
sudo -u "$target_user" -H \
  GHOSTTY_VERSION="$GHOSTTY_VERSION" \
  ZIG_VERSION="$ZIG_VERSION" \
  GHOSTTY_PUBKEY="$GHOSTTY_PUBKEY" \
  ZIG_PUBKEY="$ZIG_PUBKEY" \
  bash <<'USER_PHASE'
set -euo pipefail
IFS=$'\n\t'

local_prefix="$HOME/.local"
cache_dir="$HOME/.cache/ghostty-build"
src_dir="$HOME/src"
arch=$(uname -m)
zig_dir="$local_prefix/share/zig-${ZIG_VERSION}"
zig_link="$local_prefix/share/zig"
zig_tarball="zig-${arch}-linux-${ZIG_VERSION}.tar.xz"
ghostty_tarball="ghostty-${GHOSTTY_VERSION}.tar.gz"
ghostty_src="$src_dir/ghostty-${GHOSTTY_VERSION}"

mkdir -p "$local_prefix/bin" "$local_prefix/share" "$local_prefix/lib" "$cache_dir" "$src_dir"

step() { printf '   %s\n' "$*"; }

# --- Zig ---
installed_zig=$("$zig_link/zig" version 2>/dev/null || true)
if [[ $installed_zig == "$ZIG_VERSION" ]]; then
  step "Zig $ZIG_VERSION already installed"
else
  step "Fetching Zig $ZIG_VERSION"
  cd "$cache_dir"
  [[ -f $zig_tarball ]] || curl -fsSLO "https://ziglang.org/download/${ZIG_VERSION}/${zig_tarball}"
  [[ -f ${zig_tarball}.minisig ]] || curl -fsSLO "https://ziglang.org/download/${ZIG_VERSION}/${zig_tarball}.minisig"
  minisign -V -q -P "$ZIG_PUBKEY" -m "$zig_tarball"
  rm -rf "$zig_dir"
  tar -C "$local_prefix/share" -xf "$zig_tarball"
  mv "$local_prefix/share/zig-${arch}-linux-${ZIG_VERSION}" "$zig_dir"
  ln -sfn "$zig_dir" "$zig_link"
  ln -sfn "$zig_link/zig" "$local_prefix/bin/zig"
  step "Zig: $("$zig_link/zig" version)"
fi

# --- Ghostty source ---
if [[ -d $ghostty_src ]]; then
  step "Source already extracted at $ghostty_src"
else
  step "Fetching Ghostty $GHOSTTY_VERSION source"
  cd "$cache_dir"
  [[ -f $ghostty_tarball ]] || curl -fsSLO "https://release.files.ghostty.org/${GHOSTTY_VERSION}/${ghostty_tarball}"
  [[ -f ${ghostty_tarball}.minisig ]] || curl -fsSLO "https://release.files.ghostty.org/${GHOSTTY_VERSION}/${ghostty_tarball}.minisig"
  minisign -V -q -P "$GHOSTTY_PUBKEY" -m "$ghostty_tarball"
  tar -C "$src_dir" -xf "$ghostty_tarball"
fi

# --- Build ---
installed_ver=$("$local_prefix/bin/ghostty" --version 2>/dev/null | awk '/version:/ {print $NF; exit}' || true)
if [[ $installed_ver == "${GHOSTTY_VERSION}"* ]]; then
  step "Ghostty $GHOSTTY_VERSION already built ($installed_ver)"
else
  step "Building Ghostty (5–15 min on first build)"
  cd "$ghostty_src"
  PATH="$local_prefix/bin:$PATH" zig build \
    -p "$local_prefix" \
    -Doptimize=ReleaseFast \
    -fno-sys=gtk4-layer-shell
fi

# --- RPATH so the binary is self-contained ---
ghostty_bin="$local_prefix/bin/ghostty"
current_rpath=$(patchelf --print-rpath "$ghostty_bin" 2>/dev/null || true)
if [[ $current_rpath == *'$ORIGIN/../lib'* ]]; then
  step "RPATH already set: $current_rpath"
else
  new_rpath='$ORIGIN/../lib'
  [[ -n $current_rpath ]] && new_rpath="\$ORIGIN/../lib:${current_rpath}"
  patchelf --set-rpath "$new_rpath" "$ghostty_bin"
  step "RPATH set: $(patchelf --print-rpath "$ghostty_bin")"
fi

# --- Desktop integration ---
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$local_prefix/share/applications" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$local_prefix/share/icons/hicolor" 2>/dev/null || true
fi
step "Desktop database & icon cache refreshed"
USER_PHASE

ghostty_bin="$target_home/.local/bin/ghostty"
log "Setting Ghostty as default x-terminal-emulator"
if [[ -x $ghostty_bin ]]; then
  # Priority 50 keeps it overridable; --set pins it as the active choice.
  update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$ghostty_bin" 50 >/dev/null
  update-alternatives --set x-terminal-emulator "$ghostty_bin" >/dev/null
  printf '   x-terminal-emulator -> %s\n' \
    "$(update-alternatives --query x-terminal-emulator | awk '/^Value:/ {print $2}')"
else
  printf 'Warning: %s not executable, skipping default terminal setup\n' "$ghostty_bin" >&2
fi

infocmp xterm-ghostty | sudo tic -x /dev/stdin

ok "Ghostty $GHOSTTY_VERSION installed at $ghostty_bin"
printf '   Launch from your app menu (search "Ghostty") or run: ghostty\n'
