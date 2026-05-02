# aliases.sh — General shell aliases
# Compatible with: bash, zsh, ksh

# Directory listing
alias ll='ls -lh'
alias la='ls -lAh'
alias l='ls -CF'

# Coloured grep
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Navigation shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Terminal management
alias cls='clear'

# Shorthand
p() {
    local py

    if command -v python >/dev/null 2>&1; then
        py=python
    elif command -v python3 >/dev/null 2>&1; then
        py=python3
    else
        echo "Error: neither 'python' nor 'python3' found in PATH." >&2
        return 1
    fi

    "$py" "$@"
}

# History
alias h='history'
hgrep() {
    history | grep -i -- "$*" | awk '!seen[substr($0, index($0,$2))]++' | grep -iv -- "^[[:space:]]*[0-9]*[[:space:]]*h "
}

# Shell management
ra() {
    if [ -z "${HABITUS_SHELL_DIR:-}" ]; then
        printf 'ra: HABITUS_SHELL_DIR is not set, cannot reload\n' >&2
        return 1
    fi
    . "$HABITUS_SHELL_DIR/init.sh"
    printf 'Shell configuration reloaded.\n'
}
