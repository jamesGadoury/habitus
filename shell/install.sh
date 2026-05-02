#!/bin/sh
# Habitus shell configuration installer
# Usage: ./install.sh [--uninstall]
#
# Iterates install.d/[0-9]*.sh in sorted order (reversed for uninstall).
# Each step file defines do_install / do_uninstall functions and may use
# helpers and shared paths defined here / in install.d/_lib.sh.
#
# To add a new install step, drop a numbered file in install.d/. The
# orchestrator picks it up via the sorted glob — no edits here required.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_D="$SCRIPT_DIR/install.d"

MODE=install
case "${1:-}" in
    "")           MODE=install ;;
    --uninstall)  MODE=uninstall ;;
    -h|--help)    printf 'Usage: %s [--uninstall]\n' "$0"; exit 0 ;;
    *)            printf 'Unknown option: %s (use --uninstall to remove)\n' "$1" >&2; exit 2 ;;
esac

. "$INSTALL_D/_lib.sh"

if [ "$MODE" = uninstall ]; then
    _steps="$(ls "$INSTALL_D"/[0-9]*.sh 2>/dev/null | sort -r)"
else
    _steps="$(ls "$INSTALL_D"/[0-9]*.sh 2>/dev/null | sort)"
fi

_failures=0
for _step in $_steps; do
    [ -f "$_step" ] || continue
    _name="$(basename "$_step" .sh)"
    printf '==> %s: %s\n' "$MODE" "$_name"
    unset -f do_install do_uninstall
    . "$_step"
    if ! command -v "do_$MODE" >/dev/null 2>&1; then
        printf '    skip: no do_%s in %s\n' "$MODE" "$_name" >&2
        continue
    fi
    if ! "do_$MODE"; then
        printf '    FAILED: %s\n' "$_name" >&2
        _failures=$((_failures + 1))
    fi
done

if [ "$_failures" -gt 0 ]; then
    printf 'Completed with %d failure(s).\n' "$_failures" >&2
    exit 1
fi
printf 'Done.\n'
