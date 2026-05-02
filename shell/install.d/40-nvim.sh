# Neovim: install AppImage to ~/.local/bin/nvim, symlink nvim/ to
# ~/.config/nvim. Linux + x86_64/aarch64 only. Skips cleanly elsewhere.
# Validates that no conflicting unmanaged nvim is on PATH before installing.

_nvim_version="v0.11.6"
_nvim_dest="$HOME/.local/bin/nvim"
_nvim_version_file="$HOME/.local/bin/.nvim-version"
_nvim_config_dir="$HOME/.config/nvim"
_nvim_config_src="$REPO_DIR/nvim"
_nvim_bin_dest="$HOME/.local/bin"

_nvim_describe_owner() {
    # Classify an unmanaged nvim binary so the user knows whether to apt-purge,
    # snap-remove, or just rm it.
    _path="$1"
    if command -v dpkg >/dev/null 2>&1; then
        _pkg="$(dpkg -S "$_path" 2>/dev/null | cut -d: -f1)"
        if [ -n "$_pkg" ]; then
            printf 'dpkg package: %s' "$_pkg"
            unset _pkg
            return
        fi
    fi
    if command -v rpm >/dev/null 2>&1; then
        _pkg="$(rpm -qf "$_path" 2>/dev/null)"
        if [ -n "$_pkg" ] && [ "${_pkg#file }" = "$_pkg" ]; then
            printf 'rpm package: %s' "$_pkg"
            unset _pkg
            return
        fi
    fi
    case "$_path" in
        /snap/*) printf 'snap package'; return ;;
    esac
    printf 'unmanaged binary'
}

_nvim_validate_no_unmanaged() {
    # Walk $PATH and surface any unmanaged nvim binaries (i.e. not installed
    # by habitus). On finds, prompt the user — default abort so the conflict
    # is conscious.
    _self=""
    if [ -e "$_nvim_dest" ]; then
        _self="$(realpath "$_nvim_dest" 2>/dev/null || printf '%s' "$_nvim_dest")"
    fi

    _found=""
    _saved_ifs="$IFS"
    IFS=:
    for _dir in $PATH; do
        [ -n "$_dir" ] || continue
        _candidate="$_dir/nvim"
        [ -e "$_candidate" ] || continue
        _real="$(realpath "$_candidate" 2>/dev/null || printf '%s' "$_candidate")"
        [ -n "$_self" ] && [ "$_real" = "$_self" ] && continue
        _found="${_found}${_candidate}
"
    done
    IFS="$_saved_ifs"
    unset _dir _candidate _real _self

    [ -z "$_found" ] && return 0

    printf '\n'
    printf "${HLT}Found nvim binaries on PATH not managed by habitus:${RST}\n" >&2
    printf '%s' "$_found" | while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        printf '  %s  (%s)\n' "$_p" "$(_nvim_describe_owner "$_p")" >&2
    done
    printf '\nThese will conflict with the habitus install at %s.\n' "$_nvim_dest" >&2
    printf 'For a clean install, abort now and remove them manually.\n' >&2

    if [ ! -r /dev/tty ]; then
        die "Unmanaged nvim detected; aborting (no tty available for confirmation)"
    fi

    printf 'Continue anyway? [y/N] ' >&2
    _reply=""
    read -r _reply < /dev/tty || _reply=""
    case "$_reply" in
        y|Y|yes|YES) unset _reply _found ;;
        *) die "Aborted by user. Remove the listed nvim binaries and re-run." ;;
    esac
}

do_install() {
    case "$(uname -s)" in
        Linux) ;;
        *)
            printf 'Neovim AppImage install: skipping (Linux only)\n'
            return 0
            ;;
    esac

    if ! command -v curl >/dev/null 2>&1; then
        printf 'Neovim install: skipping (curl not found)\n' >&2
        return 0
    fi

    # Detect architecture
    _arch="$(uname -m)"
    case "$_arch" in
        x86_64)  _asset="nvim-linux-x86_64.appimage" ;;
        aarch64) _asset="nvim-linux-arm64.appimage" ;;
        *)
            printf 'Neovim install: skipping (unsupported arch: %s)\n' "$_arch" >&2
            unset _arch
            return 0
            ;;
    esac

    _nvim_validate_no_unmanaged

    # Idempotency: skip if already installed at the target version
    if [ -f "$_nvim_version_file" ] && [ "$(cat "$_nvim_version_file")" = "$_nvim_version" ] && [ -x "$_nvim_dest" ]; then
        printf 'Neovim %s already installed, skipping\n' "$_nvim_version"
    else
        _url="https://github.com/neovim/neovim/releases/download/${_nvim_version}/${_asset}"
        printf "${HLT}Downloading neovim %s (%s)...${RST}\n" "$_nvim_version" "$_asset"

        mkdir -p "$_nvim_bin_dest"
        _tmp="${_nvim_dest}.tmp.$$"
        if curl -fL -o "$_tmp" "$_url"; then
            mv "$_tmp" "$_nvim_dest"
            chmod +x "$_nvim_dest"
            printf '%s' "$_nvim_version" > "$_nvim_version_file"
            printf "${HLT}Installed neovim %s to %s${RST}\n" "$_nvim_version" "$_nvim_dest"
        else
            rm -f "$_tmp"
            printf "${HLT}Neovim download failed${RST}\n" >&2
            unset _arch _asset _url _tmp
            return 1
        fi
        unset _url _tmp

        # Verify AppImage runs; warn about FUSE if it doesn't
        if ! "$_nvim_dest" --version >/dev/null 2>&1; then
            printf '\n'
            printf "${HLT}Warning: nvim AppImage failed to run. You may need FUSE:${RST}\n" >&2
            printf '  Ubuntu/Debian:  sudo apt install libfuse2\n' >&2
            printf '  Fedora:         sudo dnf install fuse-libs\n' >&2
            printf '  Arch:           sudo pacman -S fuse2\n' >&2
            printf '\n'
        fi
    fi
    unset _arch _asset

    # Symlink neovim config from repo
    if [ -d "$_nvim_config_src" ]; then
        mkdir -p "$(dirname "$_nvim_config_dir")"
        if [ -L "$_nvim_config_dir" ]; then
            rm "$_nvim_config_dir"
        elif [ -d "$_nvim_config_dir" ]; then
            _ts="$(date '+%Y%m%d%H%M%S')"
            mv "$_nvim_config_dir" "${_nvim_config_dir}.backup.${_ts}"
            printf 'Backed up %s -> %s\n' "$_nvim_config_dir" "${_nvim_config_dir}.backup.${_ts}"
            unset _ts
        fi
        ln -s "$_nvim_config_src" "$_nvim_config_dir"
        printf 'Symlinked %s -> %s\n' "$_nvim_config_dir" "$_nvim_config_src"
    fi
}

do_uninstall() {
    # Remove neovim binary and version marker
    if [ -f "$_nvim_dest" ] || [ -L "$_nvim_dest" ]; then
        rm -f "$_nvim_dest"
        printf 'Removed %s\n' "$_nvim_dest"
    fi
    if [ -f "$_nvim_version_file" ]; then
        rm -f "$_nvim_version_file"
        printf 'Removed %s\n' "$_nvim_version_file"
    fi
    # Remove config symlink if it points to our repo
    if [ -L "$_nvim_config_dir" ]; then
        _target="$(readlink "$_nvim_config_dir")"
        case "$_target" in
            "$_nvim_config_src")
                rm "$_nvim_config_dir"
                printf 'Removed symlink %s\n' "$_nvim_config_dir"
                ;;
            *)
                printf '%s is a symlink but not managed by us, skipping\n' "$_nvim_config_dir"
                ;;
        esac
        unset _target
    fi
}
