#!/usr/bin/env bash
# Install the system packages habitus's Neovim setup needs, on Debian/Ubuntu.
# Usage: sudo ./install-nvim-deps.sh   (re-runs itself under sudo if needed)
#
# shell/install.sh installs Neovim, its plugins, Mason packages and treesitter
# parsers without root, so it can't install the system tools those rely on;
# its nvim step only warns about missing ones and points here. Each package:
#
#   unzip                       Mason unpacks zips with it and has no fallback
#                               (clangd, codelldb, deno, stylua); it also
#                               unpacks fnm in install.d/35-node.sh
#   python3, python3-venv       Mason's pypi packages (basedpyright, debugpy,
#                               clang-format) each get a venv; Debian ships
#                               the venv module separately from python3
#   build-essential             a C compiler for treesitter parsers, built on
#                               first use in nvim; make for LuaSnip's jsregexp
#   fuse3                       fusermount, which the Neovim AppImage mounts
#                               itself with; its static runtime bundles
#                               libfuse, so libfuse2 is not needed
#   ripgrep                     live grep in the picker
#   curl, git, ca-certificates  downloads and plugin clones (bare images lack
#                               them)
#
# Node and npm, for Mason's npm packages, come from install.d/35-node.sh.
# Rerun shell/install.sh as yourself afterwards so Mason retries what failed.
#
# Idempotent: apt-get skips packages that are already installed.

set -euo pipefail
IFS=$'\n\t'

readonly PACKAGES=(
  build-essential
  ca-certificates
  curl
  fuse3
  git
  python3
  python3-venv
  ripgrep
  unzip
)

# The tput probe keeps set -e from killing the script before it can explain
# itself: minimal images may lack tput (Fedora) or know no $TERM.
if [[ -t 1 && -z "${NO_COLOR:-}" ]] && tput sgr0 >/dev/null 2>&1; then
  c_info=$(tput setaf 6)
  c_ok=$(tput setaf 2)
  c_err=$(tput setaf 1)
  c_off=$(tput sgr0)
else
  c_info=''
  c_ok=''
  c_err=''
  c_off=''
fi

log() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok() { printf '%s==>%s %s\n' "$c_ok" "$c_off" "$*"; }
err() { printf '%sError:%s %s\n' "$c_err" "$c_off" "$*" >&2; }

main() {
  if ! command -v apt-get >/dev/null 2>&1; then
    err "apt-get not found; this script supports Debian and Ubuntu only."
    printf 'Elsewhere, install with your package manager: a C compiler, make, git, curl, unzip, python3 (with venv), ripgrep, and fuse3.\n' >&2
    exit 1
  fi
  if [[ $EUID -ne 0 ]]; then
    exec sudo -E "${BASH_SOURCE[0]}" "$@"
  fi

  export DEBIAN_FRONTEND=noninteractive
  log "Updating package lists"
  apt-get update -qq

  # printf, not "${PACKAGES[*]}": that joins on IFS's first character, a newline
  local list
  list=$(printf '%s ' "${PACKAGES[@]}")
  log "Installing ${list% }"
  apt-get install -y -qq --no-install-recommends "${PACKAGES[@]}" >/dev/null

  ok "Neovim's system dependencies are installed"
  printf 'Now rerun shell/install.sh as yourself (not root) so Mason retries the packages that failed.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
