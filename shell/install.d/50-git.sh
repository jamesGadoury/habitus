# Git: include managed git/config in ~/.gitconfig via [include] directive.
# Idempotent. Skips if git is missing.

_git_config_src="$REPO_DIR/git/config"

do_install() {
    if [ ! -f "$_git_config_src" ]; then
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        printf 'Git config: skipping (git not found)\n' >&2
        return 0
    fi

    # Check if the include already exists (idempotent)
    _current="$(git config --global --get-all include.path 2>/dev/null || true)"
    case "$_current" in
        *"$_git_config_src"*)
            printf 'Git config include already present, skipping\n'
            unset _current
            return 0
            ;;
    esac
    unset _current

    git config --global --add include.path "$_git_config_src" || return 1
    printf 'Added git include directive for %s\n' "$_git_config_src"
}

do_uninstall() {
    if ! command -v git >/dev/null 2>&1; then
        return 0
    fi

    _current="$(git config --global --get-all include.path 2>/dev/null || true)"
    case "$_current" in
        *"$_git_config_src"*)
            git config --global --unset "include.path" "$_git_config_src" || return 1
            printf 'Removed git include directive for %s\n' "$_git_config_src"
            ;;
        *)
            printf 'No managed git include directive found\n'
            ;;
    esac
    unset _current
}
