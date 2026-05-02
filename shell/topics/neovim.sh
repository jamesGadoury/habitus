# neovim.sh — Neovim aliases
# Compatible with: bash, zsh, ksh
# Requires: nvim

command -v nvim >/dev/null 2>&1 || return 0

alias nv='nvim'
nv_clean () {
    rm -rf ~/.local/state/nvim ~/.local/share/nvim ~/.cache/nvim
}
