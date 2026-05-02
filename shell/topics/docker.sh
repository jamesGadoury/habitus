# docker.sh — Docker aliases
# Compatible with: bash, zsh, ksh
# Requires: docker

command -v docker >/dev/null 2>&1 || return 0

alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dlogs='docker logs -f'
