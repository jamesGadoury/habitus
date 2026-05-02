# functions.sh — General-purpose utility functions
# Compatible with: bash, zsh, ksh

# Create a directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract common archive formats
extract() {
    if [ ! -f "$1" ]; then
        printf 'extract: "%s" is not a file\n' "$1" >&2
        return 1
    fi
    case "$1" in
        *.tar.bz2) tar xjf "$1"   ;;
        *.tar.gz)  tar xzf "$1"   ;;
        *.tar.xz)  tar xJf "$1"   ;;
        *.bz2)     bunzip2 "$1"   ;;
        *.gz)      gunzip "$1"    ;;
        *.tar)     tar xf "$1"    ;;
        *.tbz2)    tar xjf "$1"   ;;
        *.tgz)     tar xzf "$1"   ;;
        *.zip)     unzip "$1"     ;;
        *.Z)       uncompress "$1";;
        *.7z)      7z x "$1"      ;;
        *)         printf 'extract: unsupported format "%s"\n' "$1" >&2; return 1 ;;
    esac
}

# Copy file contents to system clipboard
cpfile() {
    if [ ! -f "$1" ]; then
        printf 'cpfile: "%s" is not a file\n' "${1:-}" >&2
        return 1
    fi
    if command -v wl-copy >/dev/null 2>&1; then
        wl-copy < "$1"
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard < "$1"
    elif command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --input < "$1"
    else
        printf 'cpfile: no clipboard tool found (install wl-copy, xclip, or xsel)\n' >&2
        return 1
    fi
}

# Find files by name pattern in current directory
fname() {
    find . -iname "*${1:-}*" 2>/dev/null
}
