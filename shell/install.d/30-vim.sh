# Vim: symlink vim/vimrc to ~/.vimrc when full vim is detected (skip vim-tiny).
# Creates ~/.vim/undodir for persistent undo.

_vimrc_src="$REPO_DIR/vim/vimrc"
_vimrc_dest="$HOME/.vimrc"
_vim_undodir="$HOME/.vim/undodir"

_vim_has_full() {
    # Check that vim exists AND is not vim-tiny (vim-tiny lacks +syntax)
    command -v vim >/dev/null 2>&1 || return 1
    vim --version 2>/dev/null | grep -q '+syntax' || return 1
}

do_install() {
    if [ ! -f "$_vimrc_src" ]; then
        return 0
    fi

    if ! _vim_has_full; then
        printf '\n'
        printf "${HLT}Warning: Full vim not found (vim-tiny lacks required features).${RST}\n" >&2
        printf '  Skipping vimrc installation.\n' >&2
        printf '  Install full vim and re-run this installer:\n' >&2
        printf '    Ubuntu/Debian:  sudo apt install vim\n' >&2
        printf '    Fedora/RHEL:    sudo dnf install vim-enhanced\n' >&2
        printf '    Arch:           sudo pacman -S vim\n' >&2
        printf '    macOS:          brew install vim\n' >&2
        printf '\n'
        return 0
    fi

    # Create undo directory for persistent undo
    mkdir -p "$_vim_undodir"

    # Symlink vimrc
    if [ -L "$_vimrc_dest" ]; then
        rm "$_vimrc_dest"
    elif [ -f "$_vimrc_dest" ]; then
        _ts="$(date '+%Y%m%d%H%M%S')"
        cp "$_vimrc_dest" "${_vimrc_dest}.backup.${_ts}"
        printf 'Backed up %s -> %s\n' "$_vimrc_dest" "${_vimrc_dest}.backup.${_ts}"
        rm "$_vimrc_dest"
        unset _ts
    fi

    ln -s "$_vimrc_src" "$_vimrc_dest"
    printf 'Symlinked %s -> %s\n' "$_vimrc_dest" "$_vimrc_src"
}

do_uninstall() {
    if [ -L "$_vimrc_dest" ]; then
        _target="$(readlink "$_vimrc_dest")"
        case "$_target" in
            "$_vimrc_src")
                rm "$_vimrc_dest"
                printf 'Removed symlink %s\n' "$_vimrc_dest"
                ;;
            *)
                printf '%s is a symlink but not managed by us, skipping\n' "$_vimrc_dest"
                ;;
        esac
        unset _target
    else
        printf 'No managed vimrc symlink found at %s\n' "$_vimrc_dest"
    fi
}
