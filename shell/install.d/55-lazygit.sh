# lazygit: install pinned lazygit and delta (its diff renderer) to
# ~/.local/bin, and symlink lazygit/config.yml to
# ${XDG_CONFIG_HOME:-~/.config}/lazygit/config.yml. Linux + x86_64/aarch64
# only. Skips cleanly elsewhere.
#
# delta is here, not in a step of its own, because only lazygit uses it: the
# config passes delta its options on the command line, and git/config keeps
# `pager = cat` for plain git on the command line.
#
# Other copies of lazygit or delta on PATH (a distro package, a hand-copied
# binary) are reported with how to remove them, but don't stop the install:
# unlike a second nvim, a second lazygit shares nothing that can go wrong, it
# just goes stale. The report says when one of them comes before ~/.local/bin
# on PATH, since that copy runs instead of the managed one.
#
# To bump either tool, change its version and both sha256 values below.
# lazygit publishes checksums.txt with each release; for delta, the GitHub
# release page lists each asset's sha256.

_lazygit_version="v0.66.2"
_lazygit_sha256_x86_64="158efc9ddfa1241fab5fb3526bb442c8dc6c4b1904d73213b9e4e93e03c52034"
_lazygit_sha256_aarch64="79a3161eeb642f0473e23db6341f7baabd4a5933e921a9c1167c5d5c765c41a4"
_lazygit_delta_version="0.20.1"
# x86_64 uses delta's static musl build: its glibc builds have needed a newer
# glibc than some current distros ship. There is no aarch64 musl build.
_lazygit_delta_sha256_x86_64="69dcb4043f55c29118f408c6efd30115e0a4e0a6709253343b8c8fa814ab4a31"
_lazygit_delta_sha256_aarch64="da7f4338f593572ff426ae153e0870e2fdc72729416eff551b40cdeb67940db8"

_lazygit_bin_dir="$HOME/.local/bin"
_lazygit_dest="$_lazygit_bin_dir/lazygit"
_lazygit_version_file="$_lazygit_bin_dir/.lazygit-version"
_lazygit_delta_dest="$_lazygit_bin_dir/delta"
_lazygit_delta_version_file="$_lazygit_bin_dir/.delta-version"
_lazygit_conf_src="$REPO_DIR/lazygit/config.yml"
_lazygit_conf_dest="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit/config.yml"

_lazygit_fetch() {
    # Download the tarball at URL $2, check it against sha256 $3, and install
    # its member $4 to $5, recording version $6 in $7. $1 names the tool in
    # messages. The binary is staged next to its destination so the final mv
    # is atomic.
    _lg_tmp="$(mktemp -d)"
    _lg_ok=0

    printf "${HLT}Downloading %s %s...${RST}\n" "$1" "$6"
    if ! curl -fL -o "$_lg_tmp/archive.tar.gz" "$2"; then
        printf '%s download failed\n' "$1" >&2
    elif [ "$(sha256sum "$_lg_tmp/archive.tar.gz" | cut -d' ' -f1)" != "$3" ]; then
        printf '%s download does not match its pinned sha256; not installing it\n' "$1" >&2
    elif ! tar -xzf "$_lg_tmp/archive.tar.gz" -C "$_lg_tmp" "$4"; then
        printf '%s archive has no %s\n' "$1" "$4" >&2
    else
        mkdir -p "$(dirname "$5")"
        cp "$_lg_tmp/$4" "${5}.tmp.$$"
        chmod +x "${5}.tmp.$$"
        mv "${5}.tmp.$$" "$5"
        printf '%s' "$6" >"$7"
        printf "${HLT}Installed %s %s to %s${RST}\n" "$1" "$6" "$5"
        _lg_ok=1
    fi

    rm -rf "$_lg_tmp"
    unset _lg_tmp
    [ "$_lg_ok" = 1 ]
}

_lazygit_ensure() {
    # Install tool $1 from URL $2 (sha256 $3, member $4) to $5 at version $6,
    # unless the marker file $7 says that version is already there.
    if [ -f "$7" ] && [ "$(cat "$7")" = "$6" ] && [ -x "$5" ]; then
        printf '%s %s already installed, skipping\n' "$1" "$6"
        return 0
    fi
    _lazygit_fetch "$@"
}

_lazygit_owner() {
    # How binary $1 got there, and the command that removes it.
    if command -v dpkg >/dev/null 2>&1; then
        _lg_pkg="$(dpkg -S "$1" 2>/dev/null | cut -d: -f1)"
        if [ -n "$_lg_pkg" ]; then
            printf 'dpkg package %s; remove with: sudo apt remove %s' "$_lg_pkg" "$_lg_pkg"
            unset _lg_pkg
            return
        fi
    fi
    if command -v rpm >/dev/null 2>&1; then
        _lg_pkg="$(rpm -qf --qf '%{NAME}' "$1" 2>/dev/null)"
        if [ -n "$_lg_pkg" ] && [ "${_lg_pkg#file }" = "$_lg_pkg" ]; then
            printf 'rpm package %s; remove with: sudo dnf remove %s' "$_lg_pkg" "$_lg_pkg"
            unset _lg_pkg
            return
        fi
    fi
    unset _lg_pkg
    case "$1" in
    /snap/*)
        printf 'snap; remove with: sudo snap remove %s' "$(basename "$1")"
        return
        ;;
    /home/linuxbrew/* | */.linuxbrew/*)
        printf 'Homebrew; remove with: brew uninstall %s' "$(basename "$1")"
        return
        ;;
    esac
    if [ -w "$(dirname "$1")" ]; then
        printf 'unmanaged binary; remove with: rm %s' "$1"
    else
        printf 'unmanaged binary; remove with: sudo rm %s' "$1"
    fi
}

_lazygit_report_others() {
    # Walk PATH for copies of command $1 other than the managed one at $2,
    # and print each with its version and how to remove it. Warn-only.
    _lg_self="$(realpath "$2" 2>/dev/null || printf '%s' "$2")"
    _lg_bin_real="$(realpath "$_lazygit_bin_dir" 2>/dev/null || printf '%s' "$_lazygit_bin_dir")"
    _lg_seen_bin=0
    _lg_found=""
    _lg_saved_ifs="$IFS"
    IFS=:
    for _lg_dir in $PATH; do
        [ -n "$_lg_dir" ] || continue
        _lg_dir_real="$(realpath "$_lg_dir" 2>/dev/null || printf '%s' "$_lg_dir")"
        [ "$_lg_dir_real" = "$_lg_bin_real" ] && _lg_seen_bin=1
        _lg_cand="$_lg_dir/$1"
        [ -x "$_lg_cand" ] || continue
        _lg_real="$(realpath "$_lg_cand" 2>/dev/null || printf '%s' "$_lg_cand")"
        [ "$_lg_real" = "$_lg_self" ] && continue
        # Only flag shadowing when ~/.local/bin is on PATH at all: if it
        # isn't yet, init.sh puts it first in every new shell.
        _lg_shadow=0
        case ":$PATH:" in
        *":$_lazygit_bin_dir:"*) [ "$_lg_seen_bin" = 0 ] && _lg_shadow=1 ;;
        esac
        _lg_found="${_lg_found}${_lg_cand}:${_lg_shadow}
"
    done
    IFS="$_lg_saved_ifs"

    if [ -n "$_lg_found" ]; then
        printf '\n'
        printf "${HLT}Found %s binaries on PATH not managed by habitus:${RST}\n" "$1" >&2
        printf '%s' "$_lg_found" | while IFS= read -r _lg_line; do
            [ -n "$_lg_line" ] || continue
            _lg_path="${_lg_line%:*}"
            # `lazygit --version` prints key=value pairs; delta prints "delta X".
            _lg_ver="$("$_lg_path" --version 2>/dev/null | head -n 1)"
            case "$_lg_ver" in
            *version=*) _lg_ver="$(printf '%s' "$_lg_ver" | sed 's/.*, version=\([^,]*\).*/\1/')" ;;
            *) _lg_ver="${_lg_ver##* }" ;;
            esac
            printf '  %s (%s)\n' "$_lg_path" "${_lg_ver:-unknown version}" >&2
            printf '    %s\n' "$(_lazygit_owner "$_lg_path")" >&2
            if [ "${_lg_line##*:}" = 1 ]; then
                printf '    comes before %s on PATH, so it runs instead of the managed copy\n' "$_lazygit_bin_dir" >&2
            fi
        done
        printf 'The managed copy is %s. Remove the others so an old version never runs by mistake.\n' "$2" >&2
        printf '\n'
    fi
    unset _lg_self _lg_bin_real _lg_seen_bin _lg_found _lg_saved_ifs _lg_dir \
        _lg_dir_real _lg_cand _lg_real _lg_shadow
}

_lazygit_link_config() {
    # Symlink the managed config into place, backing up a real file first.
    mkdir -p "$(dirname "$_lazygit_conf_dest")"
    if [ -L "$_lazygit_conf_dest" ]; then
        rm "$_lazygit_conf_dest"
    elif [ -e "$_lazygit_conf_dest" ]; then
        _lg_ts="$(date '+%Y%m%d%H%M%S')"
        cp "$_lazygit_conf_dest" "${_lazygit_conf_dest}.backup.${_lg_ts}"
        printf 'Backed up %s -> %s\n' "$_lazygit_conf_dest" "${_lazygit_conf_dest}.backup.${_lg_ts}"
        rm "$_lazygit_conf_dest"
        unset _lg_ts
    fi
    ln -s "$_lazygit_conf_src" "$_lazygit_conf_dest"
    printf 'Symlinked %s -> %s\n' "$_lazygit_conf_dest" "$_lazygit_conf_src"
}

do_install() {
    case "$(uname -s)" in
    Linux) ;;
    *)
        printf 'lazygit install: skipping (Linux only)\n'
        return 0
        ;;
    esac

    if ! command -v curl >/dev/null 2>&1; then
        printf 'lazygit install: skipping (curl not found)\n' >&2
        return 0
    fi

    _lg_arch="$(uname -m)"
    case "$_lg_arch" in
    x86_64)
        _lg_asset="linux_x86_64"
        _lg_sha="$_lazygit_sha256_x86_64"
        _lg_delta_triple="x86_64-unknown-linux-musl"
        _lg_delta_sha="$_lazygit_delta_sha256_x86_64"
        ;;
    aarch64)
        _lg_asset="linux_arm64"
        _lg_sha="$_lazygit_sha256_aarch64"
        _lg_delta_triple="aarch64-unknown-linux-gnu"
        _lg_delta_sha="$_lazygit_delta_sha256_aarch64"
        ;;
    *)
        printf 'lazygit install: skipping (unsupported arch: %s)\n' "$_lg_arch" >&2
        unset _lg_arch
        return 0
        ;;
    esac

    _lg_status=0
    _lg_bare="${_lazygit_version#v}"
    _lazygit_ensure lazygit \
        "https://github.com/jesseduffield/lazygit/releases/download/${_lazygit_version}/lazygit_${_lg_bare}_${_lg_asset}.tar.gz" \
        "$_lg_sha" lazygit "$_lazygit_dest" "$_lazygit_version" "$_lazygit_version_file" ||
        _lg_status=1

    _lg_delta_name="delta-${_lazygit_delta_version}-${_lg_delta_triple}"
    _lazygit_ensure delta \
        "https://github.com/dandavison/delta/releases/download/${_lazygit_delta_version}/${_lg_delta_name}.tar.gz" \
        "$_lg_delta_sha" "${_lg_delta_name}/delta" "$_lazygit_delta_dest" "$_lazygit_delta_version" \
        "$_lazygit_delta_version_file" ||
        _lg_status=1

    unset _lg_arch _lg_asset _lg_sha _lg_delta_triple _lg_delta_sha _lg_bare _lg_delta_name

    _lazygit_link_config

    [ -x "$_lazygit_dest" ] && _lazygit_report_others lazygit "$_lazygit_dest"
    [ -x "$_lazygit_delta_dest" ] && _lazygit_report_others delta "$_lazygit_delta_dest"

    _lg_ret="$_lg_status"
    unset _lg_status
    return "$_lg_ret"
}

do_uninstall() {
    for _lg_f in "$_lazygit_dest" "$_lazygit_version_file" \
        "$_lazygit_delta_dest" "$_lazygit_delta_version_file"; do
        if [ -f "$_lg_f" ] || [ -L "$_lg_f" ]; then
            rm -f "$_lg_f"
            printf 'Removed %s\n' "$_lg_f"
        fi
    done
    unset _lg_f

    if [ -L "$_lazygit_conf_dest" ]; then
        _lg_target="$(readlink "$_lazygit_conf_dest")"
        if [ "$_lg_target" = "$_lazygit_conf_src" ]; then
            rm "$_lazygit_conf_dest"
            printf 'Removed symlink %s\n' "$_lazygit_conf_dest"
        else
            printf '%s is a symlink but not managed by us, skipping\n' "$_lazygit_conf_dest"
        fi
        unset _lg_target
    else
        printf 'No managed lazygit config symlink found at %s\n' "$_lazygit_conf_dest"
    fi
    # lazygit's state.yml (recent repos etc.) next to the config is left alone.
}
