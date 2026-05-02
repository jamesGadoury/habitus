# git.sh — Git aliases and helpers
# Compatible with: bash, zsh, ksh
# Requires: git

command -v git >/dev/null 2>&1 || return 0

alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias glog='git log --oneline --graph --decorate'
alias gb='git branch -avv --color=always'

gsync() {
    printf 'Fetching all branches and pruning deleted ones...\n'
    git fetch --all --prune

    current=$(git symbolic-ref --short HEAD 2>/dev/null) || current=""

    git for-each-ref --format='%(refname:short) %(upstream:short) %(upstream:remotename)' refs/heads | \
    while read -r local_branch remote_branch remote_name; do
        [ -z "$remote_branch" ] && continue

        local_sha=$(git rev-parse "$local_branch")
        remote_sha=$(git rev-parse "$remote_branch" 2>/dev/null) || continue
        [ "$local_sha" = "$remote_sha" ] && continue

        if git merge-base --is-ancestor "$remote_branch" "$local_branch"; then
            # Local is ahead of remote — push
            if git push "$remote_name" "$local_branch" >/dev/null 2>&1; then
                printf '  %-20s pushed\n' "$local_branch"
            else
                printf '  %-20s push failed\n' "$local_branch"
            fi
        elif git merge-base --is-ancestor "$local_branch" "$remote_branch"; then
            # Local is behind remote — fast-forward
            if [ "$local_branch" = "$current" ]; then
                if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                    printf '  %-20s dirty worktree, skipping\n' "$local_branch"
                elif git merge --ff-only "$remote_branch" >/dev/null 2>&1; then
                    printf '  %-20s fast-forwarded\n' "$local_branch"
                else
                    printf '  %-20s fast-forward failed\n' "$local_branch"
                fi
            else
                if git update-ref "refs/heads/$local_branch" "$remote_sha" "$local_sha"; then
                    printf '  %-20s fast-forwarded\n' "$local_branch"
                else
                    printf '  %-20s update failed\n' "$local_branch"
                fi
            fi
        else
            printf '  %-20s diverged, skipping\n' "$local_branch"
        fi
    done

    printf '\nCurrent branches:\n'
    gb
}

# Add, commit, and push in one step
# Usage: gacp "commit message"
gacp() {
    if [ -z "${1:-}" ]; then
        printf 'Usage: gacp "commit message"\n' >&2
        return 1
    fi
    git add -A && git commit -m "$1" && git push
}
