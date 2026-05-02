#!/bin/sh
# disable-capslock — Disable the Caps Lock key
#
# Usage: disable-capslock [--install | --uninstall]
#
# With no arguments: disables Caps Lock for the current session.
#
# --install    Create an XDG autostart entry so this runs on login
# --uninstall  Remove the autostart entry
#
# Requires: gsettings (Wayland/GNOME) or setxkbmap (X11)

set -e

AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/disable-capslock.desktop"
SCRIPT_PATH="$(readlink -f "$0")"

install_autostart() {
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Disable Caps Lock
Exec=$SCRIPT_PATH
X-GNOME-Autostart-enabled=true
EOF
    printf 'Autostart entry created: %s\n' "$AUTOSTART_FILE"
}

uninstall_autostart() {
    if [ -f "$AUTOSTART_FILE" ]; then
        rm "$AUTOSTART_FILE"
        printf 'Autostart entry removed: %s\n' "$AUTOSTART_FILE"
    else
        printf 'No autostart entry found.\n'
    fi
}

case "${1:-}" in
    --install)   install_autostart; exit 0 ;;
    --uninstall) uninstall_autostart; exit 0 ;;
    "") ;;
    *)
        printf 'Usage: disable-capslock [--install | --uninstall]\n' >&2
        exit 1
        ;;
esac

is_wayland() {
    [ "${XDG_SESSION_TYPE:-}" = "wayland" ]
}

if is_wayland; then
    if ! command -v gsettings >/dev/null 2>&1; then
        printf 'disable-capslock: required tool "gsettings" not found\n' >&2
        exit 1
    fi
    current="$(gsettings get org.gnome.desktop.input-sources xkb-options)"
    case "$current" in
        *"'caps:none'"*) ;;
        "@as []" | "[]")
            gsettings set org.gnome.desktop.input-sources xkb-options "['caps:none']"
            ;;
        *)
            # Append caps:none to existing options
            new="$(printf '%s' "$current" | sed "s/]/, 'caps:none']/")"
            gsettings set org.gnome.desktop.input-sources xkb-options "$new"
            ;;
    esac
else
    if ! command -v setxkbmap >/dev/null 2>&1; then
        printf 'disable-capslock: required tool "setxkbmap" not found\n' >&2
        exit 1
    fi
    setxkbmap -option caps:none
fi
