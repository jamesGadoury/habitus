# node.sh — Node.js and npm via fnm (Fast Node Manager)
# Compatible with: bash, zsh (fnm has no ksh integration; skipped there)
# Requires: fnm (installed by install.d/35-node.sh)
#
# Puts fnm's default Node, and the npm bundled with it, on PATH. On cd into a
# directory with a .node-version, .nvmrc, or package.json "engines" field, it
# switches to the version that file asks for.
#   fnm list            # installed versions; `default` marks the one new shells get
#   fnm install 22      # add the newest 22.x
#   fnm use 22          # this shell only
#   fnm default 22      # new shells (install.d/35-node.sh resets it on rerun)
#
# zsh hooks the switch into chpwd. bash gets `alias cd=__fnmcd`, which calls
# `\cd`: that skips the alias but still reaches the cd() in navigation.sh.

command -v fnm >/dev/null 2>&1 || return 0

if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(fnm env --use-on-cd --shell zsh)"
elif [ -n "${BASH_VERSION:-}" ]; then
    eval "$(fnm env --use-on-cd --shell bash)"
fi
