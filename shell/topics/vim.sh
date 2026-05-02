# vim.sh — Vim environment checks
# Compatible with: bash, zsh, sh

# Warn once per session if vim lacks clipboard support
if command -v vim >/dev/null 2>&1; then
    if ! vim --version 2>/dev/null | grep -q '+clipboard'; then
        printf 'vim: clipboard support missing (yanking won'\''t reach system clipboard)\n' >&2
        printf '     install vim-gtk3 to fix: sudo apt install vim-gtk3\n' >&2
    fi
fi
