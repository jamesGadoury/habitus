#!/bin/sh
# Install/update Raspberry Pi Imager (AppImage) with desktop integration
# Usage: install-rpi-imager [--uninstall]
#
# Downloads the latest AppImage from GitHub, extracts the bundled icon,
# and creates a .desktop entry so it appears in the app launcher.

set -e

REPO="raspberrypi/rpi-imager"
APP_DIR="$HOME/.local/share/rpi-imager"
APP_DEST="$APP_DIR/rpi-imager.AppImage"
VERSION_FILE="$APP_DIR/.version"
ICON_DIR="$HOME/.local/share/icons"
ICON_DEST="$ICON_DIR/rpi-imager.svg"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_DEST="$DESKTOP_DIR/rpi-imager.desktop"

# Colors (disabled when stdout is not a terminal)
if [ -t 1 ]; then
    HLT='\033[1;33m'  # bold yellow
    RST='\033[0m'
else
    HLT=''
    RST=''
fi

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

get_latest_version() {
    # Returns the tag_name from the latest GitHub release
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"tag_name": *"//; s/"$//'
}

find_asset_url() {
    # Returns the download URL for the AppImage matching the current arch
    _tag="$1"
    _arch="$(uname -m)"
    case "$_arch" in
        x86_64)  _arch_pattern="x86_64" ;;
        aarch64) _arch_pattern="arm64"   ;;
        *)       die "Unsupported architecture: $_arch" ;;
    esac

    curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$_tag" \
        | grep -o '"browser_download_url": *"[^"]*\.AppImage"' \
        | sed 's/.*"browser_download_url": *"//; s/"$//' \
        | grep "desktop" \
        | grep "$_arch_pattern" \
        | head -1

    unset _arch _arch_pattern
}

extract_icon() {
    # Extract the SVG icon from the AppImage into the icon directory.
    # --appimage-extract writes to ./squashfs-root in the cwd, so we
    # use a temp directory to avoid polluting the install location.
    _work="$(mktemp -d)"
    _extract_dir="$_work/squashfs-root"

    _old_pwd="$(pwd)"
    cd "$_work" || { unset _work _extract_dir; return; }
    "$APP_DEST" --appimage-extract 'usr/share/icons/hicolor/scalable/apps/rpi-imager.svg' >/dev/null 2>&1 || \
    "$APP_DEST" --appimage-extract >/dev/null 2>&1 || true
    cd "$_old_pwd"
    unset _old_pwd

    # The icon may be at the hicolor path or symlinked from the root
    _icon="$_extract_dir/usr/share/icons/hicolor/scalable/apps/rpi-imager.svg"
    if [ ! -f "$_icon" ]; then
        _icon="$_extract_dir/rpi-imager.svg"
    fi

    if [ -f "$_icon" ]; then
        mkdir -p "$ICON_DIR"
        cp "$_icon" "$ICON_DEST"
        printf 'Installed icon to %s\n' "$ICON_DEST"
    else
        printf 'Warning: could not extract icon from AppImage\n' >&2
    fi

    rm -rf "$_work"
    unset _work _extract_dir
}

install_desktop_entry() {
    mkdir -p "$DESKTOP_DIR"
    cat > "$DESKTOP_DEST" <<EOF
[Desktop Entry]
Type=Application
Version=1.5
Name=Raspberry Pi Imager
Comment=Tool for writing images to SD cards for Raspberry Pi
Icon=rpi-imager
Exec=$APP_DEST %u
Categories=Utility;
StartupNotify=false
MimeType=x-scheme-handler/rpi-imager;application/vnd.raspberrypi.imager-manifest+json;
EOF
    printf 'Installed desktop entry to %s\n' "$DESKTOP_DEST"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi
}

do_install() {
    case "$(uname -s)" in
        Linux) ;;
        *) die "AppImage install is Linux only" ;;
    esac

    command -v curl >/dev/null 2>&1 || die "curl is required but not found"

    printf "${HLT}Fetching latest release info...${RST}\n"
    _version="$(get_latest_version)"
    [ -n "$_version" ] || die "Could not determine latest version"

    # Idempotency: skip if already at the latest version
    if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$_version" ] && [ -x "$APP_DEST" ]; then
        printf 'Raspberry Pi Imager %s already installed, skipping\n' "$_version"
        return
    fi

    _url="$(find_asset_url "$_version")"
    [ -n "$_url" ] || die "Could not find AppImage asset for $(uname -m)"

    printf "${HLT}Downloading Raspberry Pi Imager %s...${RST}\n" "$_version"
    mkdir -p "$APP_DIR"
    _tmp="${APP_DEST}.tmp.$$"
    if curl -fL -o "$_tmp" "$_url"; then
        mv "$_tmp" "$APP_DEST"
        chmod +x "$APP_DEST"
        printf '%s' "$_version" > "$VERSION_FILE"
        printf "${HLT}Downloaded to %s${RST}\n" "$APP_DEST"
    else
        rm -f "$_tmp"
        die "Download failed"
    fi
    unset _url _tmp

    extract_icon
    install_desktop_entry

    printf "${HLT}Raspberry Pi Imager %s installed successfully${RST}\n" "$_version"
    printf 'Search for "Raspberry Pi Imager" in your app launcher to pin it.\n'
    unset _version
}

do_uninstall() {
    _removed=0

    if [ -f "$DESKTOP_DEST" ]; then
        rm "$DESKTOP_DEST"
        printf 'Removed %s\n' "$DESKTOP_DEST"
        _removed=1
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
        fi
    fi

    if [ -f "$ICON_DEST" ]; then
        rm "$ICON_DEST"
        printf 'Removed %s\n' "$ICON_DEST"
        _removed=1
    fi

    if [ -d "$APP_DIR" ]; then
        rm -rf "$APP_DIR"
        printf 'Removed %s\n' "$APP_DIR"
        _removed=1
    fi

    if [ "$_removed" -eq 1 ]; then
        printf "${HLT}Raspberry Pi Imager uninstalled${RST}\n"
    else
        printf 'Nothing to uninstall\n'
    fi
    unset _removed
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-}" in
    --uninstall)
        do_uninstall
        ;;
    "")
        do_install
        ;;
    *)
        die "Unknown option: $1 (use --uninstall to remove)"
        ;;
esac
