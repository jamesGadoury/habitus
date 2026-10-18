# Systemd: symlink systemd/oom.conf into the user manager's user.conf.d, so an
# OOM kill takes only its victim rather than the whole terminal or tmux scope.
# Skips cleanly where systemd isn't the init system.

_systemd_oom_src="$REPO_DIR/systemd/oom.conf"
_systemd_oom_dest="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user.conf.d/habitus-oom.conf"

do_install() {
    if [ ! -f "$_systemd_oom_src" ]; then
        return 0
    fi

    # /run/systemd/system exists only when systemd is PID 1 (sd_booted(3)).
    if [ ! -d /run/systemd/system ]; then
        printf 'systemd not running, skipping user manager config\n'
        return 0
    fi

    if [ -L "$_systemd_oom_dest" ] && [ "$(readlink "$_systemd_oom_dest")" = "$_systemd_oom_src" ]; then
        printf 'Already linked %s\n' "$_systemd_oom_dest"
        return 0
    fi

    mkdir -p "$(dirname "$_systemd_oom_dest")"
    if [ -L "$_systemd_oom_dest" ]; then
        rm "$_systemd_oom_dest"
    elif [ -e "$_systemd_oom_dest" ]; then
        _ts="$(date '+%Y%m%d%H%M%S')"
        # The backup must not end in .conf, or systemd would still read it.
        cp "$_systemd_oom_dest" "${_systemd_oom_dest}.backup.${_ts}"
        printf 'Backed up %s -> %s\n' "$_systemd_oom_dest" "${_systemd_oom_dest}.backup.${_ts}"
        rm "$_systemd_oom_dest"
        unset _ts
    fi
    ln -s "$_systemd_oom_src" "$_systemd_oom_dest"
    printf 'Symlinked %s -> %s\n' "$_systemd_oom_dest" "$_systemd_oom_src"
    printf "Takes effect at next login, or now with: ${HLT}systemctl --user daemon-reexec${RST}\n"
}

do_uninstall() {
    if [ -L "$_systemd_oom_dest" ]; then
        _target="$(readlink "$_systemd_oom_dest")"
        case "$_target" in
            "$_systemd_oom_src")
                rm "$_systemd_oom_dest"
                printf 'Removed symlink %s\n' "$_systemd_oom_dest"
                ;;
            *)
                printf '%s is a symlink but not managed by us, skipping\n' "$_systemd_oom_dest"
                ;;
        esac
        unset _target
    else
        printf 'No managed systemd config symlink found at %s\n' "$_systemd_oom_dest"
    fi
}
