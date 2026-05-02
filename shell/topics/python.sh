# python.sh — uv + managed default Python environment
# Compatible with: bash, zsh, ksh
# Requires: uv (https://docs.astral.sh/uv/)

command -v uv >/dev/null 2>&1 || return 0

# `duv` = uv targeting the managed default env. UV_PROJECT is set only
# for the single command invocation (POSIX command-prefix assignment),
# so plain `uv` elsewhere is unaffected.
#   duv run python    # run python from the default env
#   duv sync          # sync default env from shell/python/pyproject.toml
#   duv add httpx     # add httpx to the default env's pyproject
duv() {
    UV_PROJECT="$HABITUS_SHELL_DIR/python" uv "$@"
}
duvp() {
    duv run python
}

# Sync the default env, selecting the torch backend extra based on
# whether an NVIDIA GPU is present. Extra args are forwarded to
# `uv sync`. After sync, prints torch / CUDA state so the install can
# be verified against the host.
duvsync() {
    local _extra
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        _extra=cu128
        printf 'duvsync: NVIDIA GPU detected, selecting cu128 wheels\n'
    else
        _extra=cpu
        printf 'duvsync: no NVIDIA GPU detected, using cpu\n'
    fi
    duv sync --extra "$_extra" "$@" || return 1
    duv run python -c 'import torch; print(f"torch={torch.__version__} cuda_build={torch.version.cuda} cuda_available={torch.cuda.is_available()}")'
}

# Edit the default env's dep manifest in $EDITOR.
pydeps() {
    if [ -z "${HABITUS_SHELL_DIR:-}" ]; then
        printf 'pydeps: HABITUS_SHELL_DIR is not set\n' >&2
        return 1
    fi
    "${EDITOR:-vi}" "$HABITUS_SHELL_DIR/python/pyproject.toml"
}
