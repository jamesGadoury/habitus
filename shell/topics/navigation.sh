# navigation.sh — Directory navigation shortcuts
# Compatible with: bash, zsh, ksh

# cd and list directory contents
cd() {
    # builtin bypasses this function to call the shell's built-in cd (avoids recursion)
    builtin cd "$@" || return
    [ -t 1 ] && ls
    return 0
}

# cd to the root of the current git repository
cdgit() {
    _root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [ -z "$_root" ]; then
        printf 'cdgit: not inside a git repository\n' >&2
        return 1
    fi
    cd "$_root"
    unset _root
}
