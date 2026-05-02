# RC file integration: append a marker-delimited source line for init.sh
# to the user's shell rc file (~/.bashrc, ~/.zshrc, ~/.kshrc).
# Also ensures shell/local.d/ exists.

_rc_init_file="$SCRIPT_DIR/init.sh"
_rc_local_dir="$SCRIPT_DIR/local.d"

do_install() {
    _rc="$(detect_rc_file)"

    # Create rc file if it doesn't exist
    if [ ! -f "$_rc" ]; then
        touch "$_rc"
        printf 'Created %s\n' "$_rc"
    else
        backup_rc "$_rc"
    fi

    # Remove old block if present (idempotent update)
    if has_marker "$_rc"; then
        remove_block "$_rc"
        printf 'Removed old habitus shell config block from %s\n' "$_rc"
    fi

    # Append new source block
    printf '\n%s\n[ -f "%s" ] && . "%s"\n%s\n' \
        "$MARKER_BEGIN" "$_rc_init_file" "$_rc_init_file" "$MARKER_END" >> "$_rc"

    # Ensure local.d directory exists
    mkdir -p "$_rc_local_dir"

    printf "${HLT}Installed habitus shell config in %s${RST}\n" "$_rc"
    printf "${HLT}Open a new terminal or run:  . %s${RST}\n" "$_rc"
}

do_uninstall() {
    _rc="$(detect_rc_file)"

    if [ ! -f "$_rc" ]; then
        printf 'Nothing to do: %s does not exist\n' "$_rc"
        return 0
    fi

    if ! has_marker "$_rc"; then
        printf 'Nothing to do: no habitus shell config block found in %s\n' "$_rc"
        return 0
    fi

    backup_rc "$_rc"
    remove_block "$_rc"
    printf "${HLT}Removed habitus shell config block from %s${RST}\n" "$_rc"
}
