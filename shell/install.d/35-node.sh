# Node.js: install fnm (Fast Node Manager) to ~/.local/bin/fnm, then the
# newest release of the Node line in HABITUS_NODE_VERSION (default below) and
# make it fnm's default. Linux + x86_64/aarch64 only. Skips cleanly elsewhere.
#
# Numbered before 40-nvim on purpose: Mason installs several language servers
# with npm, so node has to be on PATH when that step syncs them. The PATH
# change made here lasts for the rest of this install run; new shells get it
# from topics/node.sh.
#
# Rerunning picks up the line's newest patch release. To move to a new major,
# change the default below (or set HABITUS_NODE_VERSION) and rerun. To bump
# fnm, change _node_fnm_version and both checksums: the GitHub release page
# lists each asset's sha256.

_node_version="${HABITUS_NODE_VERSION:-24}"
_node_fnm_version="v1.39.0"
_node_fnm_sha256_x86_64="7807664f39d39fc518da1c35ba0181e4b3267603c4b1dedeb4b5fc6ae440a224"
_node_fnm_sha256_aarch64="4eaff58b2c5bf30d0934027572dd0b5bbb60d2a1af309230b53662d4b1d45599"
_node_fnm_dest="$HOME/.local/bin/fnm"
_node_fnm_version_file="$HOME/.local/bin/.fnm-version"

_node_unzip() {
    # Extract zip $1 into directory $2. Minimal installs often lack unzip, so
    # fall back to Python's zipfile module.
    if command -v unzip >/dev/null 2>&1; then
        unzip -oq "$1" -d "$2"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$1" "$2"
    else
        printf 'fnm install: need unzip or python3 to extract %s\n' "$1" >&2
        return 1
    fi
}

_node_install_fnm() {
    # Download the pinned fnm release for arch $1, check it against sha256 $2,
    # and move it into place. The binary is staged next to its destination so
    # the final mv is atomic.
    _node_asset="fnm-linux.zip"
    [ "$1" = aarch64 ] && _node_asset="fnm-arm64.zip"
    _node_url="https://github.com/Schniz/fnm/releases/download/${_node_fnm_version}/${_node_asset}"
    _node_tmp="$(mktemp -d)"
    _node_ok=0

    printf "${HLT}Downloading fnm %s (%s)...${RST}\n" "$_node_fnm_version" "$_node_asset"
    if ! curl -fL -o "$_node_tmp/$_node_asset" "$_node_url"; then
        printf 'fnm download failed\n' >&2
    elif [ "$(sha256sum "$_node_tmp/$_node_asset" | cut -d' ' -f1)" != "$2" ]; then
        printf 'fnm download does not match its pinned sha256; not installing it\n' >&2
    elif _node_unzip "$_node_tmp/$_node_asset" "$_node_tmp"; then
        mkdir -p "$(dirname "$_node_fnm_dest")"
        cp "$_node_tmp/fnm" "${_node_fnm_dest}.tmp.$$"
        chmod +x "${_node_fnm_dest}.tmp.$$"
        mv "${_node_fnm_dest}.tmp.$$" "$_node_fnm_dest"
        printf '%s' "$_node_fnm_version" >"$_node_fnm_version_file"
        printf "${HLT}Installed fnm %s to %s${RST}\n" "$_node_fnm_version" "$_node_fnm_dest"
        _node_ok=1
    fi

    rm -rf "$_node_tmp"
    unset _node_asset _node_url _node_tmp
    [ "$_node_ok" = 1 ]
}

do_install() {
    case "$(uname -s)" in
        Linux) ;;
        *)
            printf 'Node install: skipping (Linux only)\n'
            return 0
            ;;
    esac

    if ! command -v curl >/dev/null 2>&1; then
        printf 'Node install: skipping (curl not found)\n' >&2
        return 0
    fi

    _node_arch="$(uname -m)"
    case "$_node_arch" in
        x86_64) _node_sha256="$_node_fnm_sha256_x86_64" ;;
        aarch64) _node_sha256="$_node_fnm_sha256_aarch64" ;;
        *)
            printf 'Node install: skipping (unsupported arch: %s)\n' "$_node_arch" >&2
            unset _node_arch
            return 0
            ;;
    esac

    # Idempotency: skip the download if this fnm version is already in place
    if [ -f "$_node_fnm_version_file" ] && [ "$(cat "$_node_fnm_version_file")" = "$_node_fnm_version" ] && [ -x "$_node_fnm_dest" ]; then
        printf 'fnm %s already installed, skipping\n' "$_node_fnm_version"
    elif ! _node_install_fnm "$_node_arch" "$_node_sha256"; then
        unset _node_arch _node_sha256
        return 1
    fi
    unset _node_arch _node_sha256

    # `fnm install` is a no-op (with a warning) when the newest release of the
    # line is already installed; `fnm default` resolves to the newest one
    # installed.
    printf "${HLT}Installing Node %s with fnm...${RST}\n" "$_node_version"
    "$_node_fnm_dest" install "$_node_version" || return 1
    "$_node_fnm_dest" default "$_node_version" || return 1

    # Put the default node on PATH for the steps after this one. Without
    # --use-on-cd, `fnm env` prints only export lines, which sh can eval.
    eval "$("$_node_fnm_dest" env --shell bash)"
    printf "${HLT}fnm default is node %s, npm %s${RST}\n" "$(node --version)" "$(npm --version)"
}

do_uninstall() {
    # Remove the fnm binary and version marker. The Node versions fnm
    # installed are left alone; without fnm, topics/node.sh puts none of them
    # on PATH.
    if [ -f "$_node_fnm_dest" ] || [ -L "$_node_fnm_dest" ]; then
        rm -f "$_node_fnm_dest"
        printf 'Removed %s\n' "$_node_fnm_dest"
    fi
    if [ -f "$_node_fnm_version_file" ]; then
        rm -f "$_node_fnm_version_file"
        printf 'Removed %s\n' "$_node_fnm_version_file"
    fi
    _node_dir="${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
    if [ -d "$_node_dir" ]; then
        printf 'Left the Node versions fnm installed in %s; remove that directory to reclaim the space\n' "$_node_dir"
    fi
    unset _node_dir
}
