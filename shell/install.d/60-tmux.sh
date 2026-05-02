# Tmux: symlink tmux/tmux.conf to ~/.tmux.conf and clone TPM to
# ~/.tmux/plugins/tpm so the bundled plugin list works on first launch.

_tmux_conf_src="$REPO_DIR/tmux/tmux.conf"
_tmux_conf_dest="$HOME/.tmux.conf"
_tmux_tpm_dir="$HOME/.tmux/plugins/tpm"
_tmux_tpm_repo="https://github.com/tmux-plugins/tpm"

do_install() {
    if [ ! -f "$_tmux_conf_src" ]; then
        return 0
    fi

    if ! command -v tmux >/dev/null 2>&1; then
        printf '\n'
        printf "${HLT}Warning: tmux not found — skipping tmux config.${RST}\n" >&2
        printf '  Ubuntu/Debian:  sudo apt install tmux\n' >&2
        printf '  Fedora/RHEL:    sudo dnf install tmux\n' >&2
        printf '  Arch:           sudo pacman -S tmux\n' >&2
        printf '  macOS:          brew install tmux\n' >&2
        printf '\n'
        return 0
    fi

    # Symlink config (back up any existing real file before replacing)
    if [ -L "$_tmux_conf_dest" ]; then
        rm "$_tmux_conf_dest"
    elif [ -e "$_tmux_conf_dest" ]; then
        _ts="$(date '+%Y%m%d%H%M%S')"
        cp "$_tmux_conf_dest" "${_tmux_conf_dest}.backup.${_ts}"
        printf 'Backed up %s -> %s\n' "$_tmux_conf_dest" "${_tmux_conf_dest}.backup.${_ts}"
        rm "$_tmux_conf_dest"
        unset _ts
    fi
    ln -s "$_tmux_conf_src" "$_tmux_conf_dest"
    printf 'Symlinked %s -> %s\n' "$_tmux_conf_dest" "$_tmux_conf_src"

    # Clone TPM (idempotent: skip if dir exists; warn if git missing)
    if [ -d "$_tmux_tpm_dir" ]; then
        printf 'TPM already present at %s, skipping clone\n' "$_tmux_tpm_dir"
    elif ! command -v git >/dev/null 2>&1; then
        printf "${HLT}Warning: git not found — cannot clone TPM.${RST}\n" >&2
        printf '  Install git, then re-run the installer.\n' >&2
    else
        mkdir -p "$(dirname "$_tmux_tpm_dir")"
        if git clone --depth 1 "$_tmux_tpm_repo" "$_tmux_tpm_dir"; then
            printf "${HLT}Cloned TPM to %s${RST}\n" "$_tmux_tpm_dir"
            printf "Open tmux and press ${HLT}prefix + I${RST} (capital i) to install plugins.\n"
        else
            printf "${HLT}TPM clone failed${RST}\n" >&2
            return 1
        fi
    fi
}

do_uninstall() {
    if [ -L "$_tmux_conf_dest" ]; then
        _target="$(readlink "$_tmux_conf_dest")"
        case "$_target" in
            "$_tmux_conf_src")
                rm "$_tmux_conf_dest"
                printf 'Removed symlink %s\n' "$_tmux_conf_dest"
                ;;
            *)
                printf '%s is a symlink but not managed by us, skipping\n' "$_tmux_conf_dest"
                ;;
        esac
        unset _target
    else
        printf 'No managed tmux.conf symlink found at %s\n' "$_tmux_conf_dest"
    fi
    # Leave ~/.tmux/plugins/tpm and plugin clones in place; user state is theirs.
}
