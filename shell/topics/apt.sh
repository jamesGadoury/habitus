# apt.sh — apt maintenance convenience functions
# Compatible with: bash, zsh, ksh
# Requires: apt-get (Debian/Ubuntu)

command -v apt-get >/dev/null 2>&1 || return 0

# Full system maintenance: refresh package lists, upgrade everything
# (including transitive removals), prune orphaned dependencies with
# their config files, and drop obsolete .deb files from the cache.
# Stops at the first failing step so problems aren't masked.
aptup() {
    sudo apt-get update \
        && sudo apt-get -y full-upgrade \
        && sudo apt-get -y --purge autoremove \
        && sudo apt-get -y autoclean
}
