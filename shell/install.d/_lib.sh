# Shared helpers for habitus install steps.
# Sourced by ../install.sh before any numbered step file.
# POSIX sh — match init.sh / topics/ conventions.

# Colors (disabled when stdout is not a terminal)
if [ -t 1 ]; then
    HLT='\033[1;33m'  # bold yellow
    RST='\033[0m'
else
    HLT=''
    RST=''
fi

# Marker strings — must stay byte-identical across releases so existing
# installs upgrade cleanly (has_marker / remove_block match on these).
MARKER_BEGIN="# >>> habitus shell config >>>"
MARKER_END="# <<< habitus shell config <<<"

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

detect_rc_file() {
    case "$(basename "${SHELL:-/bin/sh}")" in
        bash) printf '%s/.bashrc\n' "$HOME" ;;
        zsh)  printf '%s/.zshrc\n'  "$HOME" ;;
        ksh)  printf '%s/.kshrc\n'  "$HOME" ;;
        *)    die "Unsupported shell: $SHELL (expected bash, zsh, or ksh)" ;;
    esac
}

has_marker() {
    grep -qF "$MARKER_BEGIN" "$1" 2>/dev/null
}

remove_block() {
    # Remove everything between (and including) the marker lines, and the
    # blank lines directly above the begin marker. 10-rc.sh writes one blank
    # line above the block; leaving it behind added a blank line to the rc
    # file on every reinstall. Dropping the whole run also clears the ones
    # earlier installs left. Blank lines are held back until the next
    # non-blank line shows whether they sit above the block.
    _rc="$1"
    _tmp="${_rc}.mgmt_tmp.$$"
    awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
        $0 == begin { blanks=0; skip=1; next }
        $0 == end   { skip=0; next }
        skip        { next }
        $0 == ""    { blanks++; next }
                    { for (; blanks > 0; blanks--) print ""; print }
        END         { for (; blanks > 0; blanks--) print "" }
    ' "$_rc" > "$_tmp"
    mv "$_tmp" "$_rc"
}

backup_rc() {
    _rc="$1"
    _ts="$(date '+%Y%m%d%H%M%S')"
    cp "$_rc" "${_rc}.backup.${_ts}"
    printf 'Backed up %s -> %s\n' "$_rc" "${_rc}.backup.${_ts}"
}
