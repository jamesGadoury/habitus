# Bin: symlink every executable in shell/bin/ into ~/.local/bin.
# Uninstall is self-aware: only removes symlinks pointing back into shell/bin/.

_bin_src="$SCRIPT_DIR/bin"
_bin_dest="$HOME/.local/bin"

do_install() {
    _count=0
    for _script in "$_bin_src"/*; do
        [ -f "$_script" ] || continue
        _name="$(basename "$_script")"
        [ "$_name" = ".gitkeep" ] && continue
        if [ ! -x "$_script" ]; then
            printf 'Warning: %s is not executable, skipping\n' "$_name" >&2
            continue
        fi
        mkdir -p "$_bin_dest"
        # Remove stale symlink or warn about conflicts
        if [ -L "$_bin_dest/$_name" ]; then
            rm "$_bin_dest/$_name"
        elif [ -e "$_bin_dest/$_name" ]; then
            printf 'Warning: %s/%s exists and is not a symlink, skipping\n' "$_bin_dest" "$_name" >&2
            continue
        fi
        ln -s "$_script" "$_bin_dest/$_name"
        _count=$((_count + 1))
    done
    if [ "$_count" -gt 0 ]; then
        printf 'Symlinked %d script(s) to %s\n' "$_count" "$_bin_dest"
    fi
    unset _count _script _name
}

do_uninstall() {
    _count=0
    for _link in "$_bin_dest"/*; do
        [ -L "$_link" ] || continue
        _target="$(readlink "$_link")"
        case "$_target" in
            "$_bin_src"/*)
                rm "$_link"
                _count=$((_count + 1))
                printf 'Removed symlink %s\n' "$_link"
                ;;
        esac
    done
    if [ "$_count" -gt 0 ]; then
        printf 'Removed %d symlink(s) from %s\n' "$_count" "$_bin_dest"
    else
        printf 'No managed symlinks found in %s\n' "$_bin_dest"
    fi
    unset _count _link _target
}
