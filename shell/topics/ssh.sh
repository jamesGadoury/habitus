# ssh.sh — Push local terminfo to remote hosts on first ssh
# Compatible with: bash, zsh, ksh, posix sh
#
# Most remote hosts don't ship the xterm-ghostty terminfo entry, so on
# fresh boxes commands like clear/tput/vim/less greet you with
# "unknown terminal type". This wrapper pushes the local entry on the
# first ssh to a given (user,host,port) and caches a marker locally so
# subsequent calls skip the push. Best-effort: if the push fails (no
# key auth, no tic on the remote, etc.) the real ssh still runs and no
# marker is written, so the next call retries. To force re-push (e.g.
# after a Ghostty update), `rm -rf ~/.cache/ghostty-terminfo`.

command -v infocmp >/dev/null 2>&1 || return 0

ssh() {
    if [ "${TERM:-}" = "xterm-ghostty" ]; then
        _ssh_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ghostty-terminfo"
        # ssh -G resolves the canonical (user,host,port) using the same
        # config parsing as a real connection but does no network I/O.
        _ssh_key=$(command ssh -G "$@" 2>/dev/null | awk '
            /^hostname / {h=$2} /^port / {p=$2} /^user / {u=$2}
            END {if (h) printf "%s@%s:%s", u, h, p}')
        _ssh_marker=""
        if [ -n "$_ssh_key" ]; then
            _ssh_marker="$_ssh_cache_dir/$(printf '%s' "$_ssh_key" | tr -c 'A-Za-z0-9._@:-' '_')"
        fi
        if [ -z "$_ssh_marker" ] || [ ! -f "$_ssh_marker" ]; then
            if infocmp -x "$TERM" 2>/dev/null |
                command ssh -o BatchMode=yes -o ConnectTimeout=5 "$@" -- \
                    'tic -x - >/dev/null 2>&1' >/dev/null 2>&1; then
                [ -n "$_ssh_marker" ] && mkdir -p "$_ssh_cache_dir" && touch "$_ssh_marker"
            fi
        fi
        unset _ssh_cache_dir _ssh_key _ssh_marker
    fi
    command ssh "$@"
}
