# Habitus shell configuration loader
# Sourced from ~/.bashrc, ~/.zshrc, or ~/.kshrc via install.sh
# Do not execute this file directly — it must be sourced.

_habitus_shell_init() {
    # Determine this script's directory
    if [ -n "${BASH_VERSION:-}" ]; then
        HABITUS_SHELL_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
    elif [ -n "${ZSH_VERSION:-}" ]; then
        HABITUS_SHELL_DIR="$(realpath "$(dirname "${(%):-%x}")")"
    elif [ -n "${KSH_VERSION:-}" ]; then
        HABITUS_SHELL_DIR="$(realpath "$(dirname "${.sh.file}")")"
    else
        # Fallback: assume the script is sourced from the repo
        HABITUS_SHELL_DIR="${HABITUS_SHELL_DIR:-}"
        if [ -z "$HABITUS_SHELL_DIR" ]; then
            printf 'habitus-shell: unable to determine HABITUS_SHELL_DIR, skipping init\n' >&2
            return 1
        fi
    fi
    export HABITUS_SHELL_DIR

    # Ensure ~/.local/bin is on PATH (for scripts installed by install.sh)
    case ":${PATH}:" in
        *":$HOME/.local/bin:"*) ;;
        *) PATH="$HOME/.local/bin:$PATH" ;;
    esac

    # Handle zsh empty-glob safety
    if [ -n "${ZSH_VERSION:-}" ]; then
        setopt NULL_GLOB
    fi

    # Source all topic files in sorted order
    for _habitus_f in "$HABITUS_SHELL_DIR"/topics/*.sh; do
        [ -f "$_habitus_f" ] && . "$_habitus_f"
    done

    # Source machine-specific overrides in sorted order
    for _habitus_f in "$HABITUS_SHELL_DIR"/local.d/*.sh; do
        [ -f "$_habitus_f" ] && . "$_habitus_f"
    done

    unset _habitus_f
}

_habitus_shell_init
unset -f _habitus_shell_init
