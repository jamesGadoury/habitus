# Clipboard: warn if the session-appropriate clipboard helper is missing.
#
# Warn-only, like the vim and tmux steps — habitus does not install packages.
#
# Why this needs its own check rather than "is any clipboard tool present":
# several things habitus ships reach for a clipboard helper, and they disagree
# about which ones are acceptable.
#
#   consumer           tries, in order            configured by
#   -----------------  -------------------------  ------------------------
#   tmux-yank (TPM)    wl-copy, xsel, xclip       tmux/tmux.conf
#   cpfile             wl-copy, xclip, xsel       shell/topics/functions.sh
#   Claude Code paste  wl-paste, xclip            (external tool)
#
# A machine with only xsel satisfies the first two and fails the third, which
# presents as "copy/paste works fine, but pasting an image into Claude Code
# says the clipboard is empty". So we assert the helper matching the session
# type — which is also the one every consumer above tries first: wl-clipboard
# under Wayland, xclip under X11.

_clip_pkg=""
_clip_missing=""

# Echo the session type we should install a clipboard helper for.
_clip_session() {
    # Darwin has pbcopy/pbpaste in the base system; nothing to check.
    if [ "$(uname -s)" = Darwin ]; then
        printf 'darwin\n'
        return 0
    fi
    # Wayland is tested first on purpose: a GNOME Wayland session also sets
    # DISPLAY for XWayland, but the Wayland helpers are the ones that work.
    if [ "${XDG_SESSION_TYPE:-}" = wayland ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        printf 'wayland\n'
    elif [ "${XDG_SESSION_TYPE:-}" = x11 ] || [ -n "${DISPLAY:-}" ]; then
        printf 'x11\n'
    else
        printf 'none\n'
    fi
}

# Populate _clip_pkg / _clip_missing for the given session type.
# Returns 0 when everything needed is present, 1 when something is missing.
_clip_check() {
    _clip_pkg=""
    _clip_missing=""
    case "$1" in
        wayland)
            _clip_pkg="wl-clipboard"
            for _clip_cmd in wl-copy wl-paste; do
                command -v "$_clip_cmd" >/dev/null 2>&1 || \
                    _clip_missing="${_clip_missing}${_clip_missing:+ }${_clip_cmd}"
            done
            ;;
        x11)
            _clip_pkg="xclip"
            command -v xclip >/dev/null 2>&1 || _clip_missing="xclip"
            ;;
        *)
            return 0
            ;;
    esac
    unset _clip_cmd
    [ -z "$_clip_missing" ]
}

do_install() {
    _clip_type="$(_clip_session)"

    case "$_clip_type" in
        darwin)
            printf 'macOS: pbcopy/pbpaste are built in, nothing to check.\n'
            unset _clip_type
            return 0
            ;;
        none)
            printf 'No graphical session detected (XDG_SESSION_TYPE=%s) — skipping clipboard check.\n' \
                "${XDG_SESSION_TYPE:-unset}"
            unset _clip_type
            return 0
            ;;
    esac

    if _clip_check "$_clip_type"; then
        printf 'Clipboard helper for %s session present (%s).\n' "$_clip_type" "$_clip_pkg"
        unset _clip_type
        return 0
    fi

    printf '\n'
    printf "${HLT}Warning: %s not found — clipboard integration is incomplete.${RST}\n" \
        "$_clip_missing" >&2
    printf '  Detected a %s session, which wants the %s package.\n' \
        "$_clip_type" "$_clip_pkg" >&2
    printf '  Without it, pasting images into Claude Code fails even though\n' >&2
    printf '  tmux-yank and cpfile still work via a fallback helper.\n' >&2
    printf '\n' >&2
    printf '  Ubuntu/Debian:  sudo apt install %s\n' "$_clip_pkg" >&2
    printf '  Fedora/RHEL:    sudo dnf install %s\n' "$_clip_pkg" >&2
    printf '  Arch:           sudo pacman -S %s\n' "$_clip_pkg" >&2
    printf '\n'

    unset _clip_type
    # Warn-only: a missing package is not an install failure.
    return 0
}

do_uninstall() {
    # Nothing is installed by this step, so there is nothing to remove.
    # Any clipboard package on the box was installed by hand and stays.
    printf 'No clipboard files managed by habitus, nothing to remove.\n'
}
