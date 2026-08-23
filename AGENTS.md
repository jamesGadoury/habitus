# Habitus — Agent Instructions

## Directory Structure

```
git/
└── config           # Managed gitconfig, included via [include] directive in ~/.gitconfig

nvim/                # Neovim (AstroNvim) config, symlinked to ~/.config/nvim
└── assets/          # Static files plugins read at runtime (markdown preview page,
                     #   its Catppuccin stylesheet, and vendor/ browser libraries)

shell/
├── init.sh             # Loader — sourced from rc file, sources all topic files
├── install.sh          # Installer orchestrator — iterates install.d/[0-9]*.sh in sorted order
├── install.d/          # Numbered install steps (sourced); _lib.sh holds shared helpers
├── bin/                # Standalone executable scripts, symlinked to ~/.local/bin
├── topics/*.sh         # Auto-sourced topic files, split by concern
├── python/             # Default Python env: pyproject.toml + uv.lock (.venv gitignored)
└── local.d/*.sh        # Gitignored machine-specific overrides

setup/               # Optional install scripts (ghostty, rpi-imager, capslock disable)
vim/                 # Vim config (vimrc symlinked to ~/.vimrc)
```

## Runtime Assets (`nvim/assets/`)

Files here are read by plugins at runtime, not by Lua's `require`. Locate them
with `vim.fn.stdpath "config"`, never a hard-coded repo path — `nvim/` is
symlinked to `~/.config/nvim` and the clone itself may live anywhere.

- `index.html` — the markdown preview page. It **shadows** the copy shipped by
  `selimacerbas/markdown-preview.nvim`: that plugin resolves its template with
  `nvim_get_runtime_file("assets/index.html", false)`, and `~/.config/nvim` is
  the first `runtimepath` entry, so ours wins without patching anything inside
  the plugin directory (and keeps winning across `:Lazy update`). The file
  records the upstream commit it was forked from; the diff against upstream is
  deliberately narrow — CDN URLs swapped for `./vendor`, one ESM import swapped
  for the UMD global, and a CSP added — so it stays cheap to re-apply.
  Every `__PLACEHOLDER__` in it is substituted by the plugin at write time and
  must be preserved verbatim.
- `markdown-preview.css` — Catppuccin theme, inlined by the plugin's
  `custom_css` option *after* its own styles. Presentation lives here rather
  than in `index.html` so restyling never touches the fork.
- `vendor/` — pinned, checksummed browser libraries (mermaid, KaTeX,
  markdown-it, highlight.js, …) so the preview fetches nothing from the network.
  `manifest.txt` is the source of truth; `shell/bin/fetch-md-preview-vendor`
  populates and verifies it. To bump a version: edit the URL in the manifest,
  run the script with `--update`, review the diff, commit.

**Rule:** if a plugin needs a runtime asset, add it here and reference it via
`stdpath`. If that asset is third-party code fetched from the internet, pin it
in `vendor/manifest.txt` with a checksum rather than letting the page load it
from a CDN.

## Default Python Environment

`shell/topics/python.sh` exposes a managed default Python env via `uv`.
Deps are declared in `shell/python/pyproject.toml`; the venv lives at
`shell/python/.venv` (gitignored) and `uv.lock` is committed. The topic
defines a `duv` wrapper that runs `uv` with `UV_PROJECT` scoped to the
default env for one invocation only, leaving plain `uv` untouched.

PyTorch is declared as mutually-exclusive `cpu` / `cu128` extras with
per-index sources (see `tool.uv.sources` / `tool.uv.index` in
`shell/python/pyproject.toml`). `duvsync` probes `nvidia-smi` and picks
the right extra, so the same pyproject works across GPU and CPU hosts.

Workflow:
- `duvsync` — sync the default env, auto-selecting the torch backend for this host
- `duv run python` (or `duvp`) — run python from the default env
- `duv add <pkg>` — add a dep to the default env
- `pydeps` — open `pyproject.toml` in `$EDITOR`

`init.sh` sources all `topics/*.sh` in sorted order, then all `local.d/*.sh`. It also ensures `~/.local/bin` is on `PATH`.

## Adding a New Topic File

1. Create `topics/<name>.sh`
2. Add a header comment: description and compatibility note
3. Follow POSIX conventions (see below)
4. If the topic depends on an optional tool, guard the entire file:
   ```sh
   command -v <tool> >/dev/null 2>&1 || return 0
   ```

That's it — `init.sh` picks it up automatically via the sorted glob.

## Adding a New Install Step

Install steps live in `shell/install.d/` as files named `<NN>-<name>.sh` (two-digit prefix; existing steps use increments of 10 to leave room for inserts). Each is sourced by `install.sh` in sorted order — reverse order for `--uninstall`.

1. Create `shell/install.d/<NN>-<name>.sh`
2. Define two functions; both must be idempotent and return 0 on success:
   ```sh
   do_install()   { ... }
   do_uninstall() { ... }
   ```
3. Use shared helpers from `install.d/_lib.sh` (`die`, `backup_rc`, `has_marker`, `remove_block`, `detect_rc_file`, `MARKER_BEGIN`/`MARKER_END`, `HLT`/`RST`).
4. Prefix step-local variables with `_<step>_` (e.g. `_nvim_dest`) so they don't collide across sourced files.
5. The orchestrator exposes `SCRIPT_DIR` (the `shell/` dir) and `REPO_DIR` (its parent) as cross-cutting paths.

The orchestrator picks the file up automatically via the sorted glob. Files starting with `_` (like `_lib.sh`) are skipped.

## Aliases vs Functions vs Scripts

- **Alias**: simple command shortcuts (`alias gs='git status'`)
- **Function**: anything that needs arguments, logic, or local variables
- **Script**: if it's long or standalone, place it in `bin/` and `chmod +x` it. `install.sh` symlinks it to `~/.local/bin`. Must have a shebang line (e.g., `#!/bin/sh`)

## Shell Compatibility Rules

- POSIX by default: `[ ]` not `[[ ]]`, `. file` not `source file`, `printf` not `echo -e`
- Guard bash-specific code: `[ -n "${BASH_VERSION:-}" ]`
- Guard zsh-specific code: `[ -n "${ZSH_VERSION:-}" ]`
- Guard optional tools: `command -v <tool> >/dev/null 2>&1`

## Do Not Modify

- **`init.sh`** — unless changing the loading mechanism itself
- **`install.sh`** (the orchestrator) and **`install.d/_lib.sh`** — unless changing the install/uninstall mechanism itself. Numbered step files in `install.d/` are normal editable code.

## Never Commit

- Files in `local.d/` — this directory is gitignored for machine-specific config

## Privileged Scripts

Scripts that require root cannot be run directly by the agent. See global CLAUDE.md for handling.

## Commits

Do not add `Co-Authored-By` trailers (or any other authorship trailers) to commit messages in this repo.
