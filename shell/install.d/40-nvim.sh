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

_nvim_lock_commits() {
    # "name commit" per plugin, sorted. Branch is left out on purpose: lazy
    # records a detached checkout's branch from the clone's origin/HEAD, which
    # `git fetch` never updates, so an old clone keeps saying `master` after
    # upstream renamed to `main`. It changes nothing about what is checked out.
    sed -n 's/^ *"\([^"]*\)": { "branch": "[^"]*", "commit": "\([^"]*\)" }.*/\1 \2/p' "$1" | sort
}

_nvim_sync_plugins() {
    # Make this machine's plugins match nvim/lazy-lock.json exactly, and its
    # Mason packages and treesitter parsers match the versions pinned in the
    # repo (plugins/mason.lua; nvim-treesitter's lockfile). The
    # lockfile is the source of truth; this step never rewrites it with
    # whatever a machine happens to have checked out.
    #
    # Needed because nothing else does it: at startup lazy.nvim only clones
    # plugins whose directory is *missing*, and never moves an existing
    # checkout. A `:Lazy update` on one box, or a spec that changes repos
    # under the same directory name, leaves it off the lockfile for good.
    #
    # Two nvim runs, with the lockfile saved in between, because lazy's
    # `install` and `clean` both end by rewriting the lockfile -- in memory
    # and on disk -- from the current checkouts (so does the install lazy does
    # at startup when a plugin is missing). A `restore` in the same process
    # would then "restore" to the drift it was meant to undo.
    #   1. install  clones absent plugins (restore skips uninstalled ones)
    #      clean    drops directories no spec claims any more
    #   2. put the saved lockfile back, then restore in a fresh process:
    #      nothing is missing now, so the lock it reads is the real one. It
    #      re-clones on a changed remote and checks out every locked commit.
    # The bang makes each verb non-interactive and blocking.
    #
    # Afterwards the lockfile is left exactly as it was unless the plugin set
    # really differs from it: a plugin added to or removed from the spec, or
    # a locked commit that could not be checked out. Then the rewritten file
    # stays, as a diff for you to review.
    if [ ! -x "$_nvim_dest" ]; then
        printf 'Neovim plugin sync: skipping (no %s)\n' "$_nvim_dest"
        return 0
    fi
    if [ ! -e "$_nvim_config_dir" ]; then
        printf 'Neovim plugin sync: skipping (no config at %s)\n' "$_nvim_config_dir"
        return 0
    fi
    _nvim_lock="$_nvim_config_src/lazy-lock.json"
    if [ ! -f "$_nvim_lock" ]; then
        printf 'Neovim plugin sync: skipping (no %s)\n' "$_nvim_lock"
        unset _nvim_lock
        return 0
    fi

    # Bounded so a wedged headless nvim cannot hang the installer. Generous:
    # a first run on a fresh machine downloads every plugin.
    _nvim_timeout=""
    if command -v timeout >/dev/null 2>&1; then
        _nvim_timeout="timeout 900"
    fi
    _nvim_saved="$(mktemp)"
    cp "$_nvim_lock" "$_nvim_saved"

    printf "${HLT}Syncing neovim plugins to lazy-lock.json...${RST}\n"
    # Never fatal: an offline or rate-limited machine should still walk away
    # with a working nvim binary and config symlink from this step.
    _nvim_ok=1
    $_nvim_timeout "$_nvim_dest" --headless "+Lazy! install" "+Lazy! clean" +qa || _nvim_ok=0
    cp "$_nvim_saved" "$_nvim_lock"
    if [ "$_nvim_ok" = 1 ]; then
        $_nvim_timeout "$_nvim_dest" --headless "+Lazy! restore" +qa || _nvim_ok=0
    fi

    # 3. Mason packages to the versions pinned in plugins/mason.lua (and
    #    uninstall any it doesn't list: mason-lspconfig enables every
    #    installed server, so a leftover one changes behaviour), then rebuild
    #    parsers whose revision differs from nvim-treesitter's own lockfile,
    #    which the restore above may just have moved. Needs the pinned
    #    plugins, hence its own process after the restore.
    if [ "$_nvim_ok" = 1 ]; then
        $_nvim_timeout "$_nvim_dest" --headless \
            "+MasonToolsInstallSync" "+MasonToolsClean" "+TSUpdateSync" +qa || _nvim_ok=0
    fi

    if [ "$_nvim_ok" = 0 ]; then
        cp "$_nvim_saved" "$_nvim_lock"
        printf 'Neovim plugin sync failed; rerun install.sh, or in nvim run :Lazy restore, :MasonToolsInstallSync, :TSUpdateSync. Continuing.\n' >&2
    elif [ "$(_nvim_lock_commits "$_nvim_saved")" = "$(_nvim_lock_commits "$_nvim_lock")" ]; then
        cp "$_nvim_saved" "$_nvim_lock"
        printf 'Neovim plugins synced\n'
    else
        printf "${HLT}Neovim plugins differ from lazy-lock.json:${RST}\n" >&2
        _nvim_lock_commits "$_nvim_saved" > "$_nvim_saved.commits"
        _nvim_lock_commits "$_nvim_lock" | diff "$_nvim_saved.commits" - | sed -n 's/^[<>]/  &/p' >&2
        printf '  (< lockfile, > installed) Review with git diff and commit if intended.\n' >&2
        rm -f "$_nvim_saved.commits"
    fi
    rm -f "$_nvim_saved"
    unset _nvim_timeout _nvim_lock _nvim_saved _nvim_ok
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

    # Last: needs both the binary above and the config symlink just made.
    _nvim_sync_plugins
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
