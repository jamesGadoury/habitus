```
░█░█░█▀█░█▀▄░▀█▀░▀█▀░█░█░█▀▀
░█▀█░█▀█░█▀▄░░█░░░█░░█░█░▀▀█
░▀░▀░▀░▀░▀▀░░▀▀▀░░▀░░▀▀▀░▀▀▀
```

Portable shell + editor config + provisioning scripts. Install once, use on any machine.

## Setup

```sh
git clone https://github.com/<user>/habitus.git ~/workspaces/habitus
~/workspaces/habitus/shell/install.sh
```

This:

- adds a source line for `shell/init.sh` to your rc file (bash/zsh/ksh)
- symlinks `shell/bin/*` into `~/.local/bin`
- symlinks `vim/vimrc` to `~/.vimrc` (if full vim is installed)
- downloads the neovim AppImage and symlinks `nvim/` to `~/.config/nvim`
- adds an `[include]` directive in `~/.gitconfig` for `git/config`

Open a new terminal to activate.

To update after a `git pull`, re-run `./shell/install.sh`.

To uninstall:

```sh
./shell/install.sh --uninstall
```

## What's inside

```
habitus/
├── git/             # Managed gitconfig (included from ~/.gitconfig)
├── nvim/            # AstroNvim config — symlinked to ~/.config/nvim
├── setup/           # Optional installers: ghostty, rpi-imager, capslock disable
├── shell/
│   ├── bin/         # Standalone scripts → ~/.local/bin (e.g. system-eval)
│   ├── topics/      # Auto-sourced aliases, functions, helpers
│   ├── python/      # Default uv-managed Python env (pyproject + lockfile)
│   └── local.d/     # Machine-specific overrides (gitignored)
└── vim/             # Vim config
```

## Per-machine extensions

Drop any shell file into `shell/local.d/*.sh` to add machine-specific config.
Anything in that directory is gitignored and sourced automatically by
`init.sh` after the topic files.

## Optional install scripts

Run individually as needed:

```sh
./setup/install-ghostty.sh        # build ghostty terminal from source
./setup/install-rpi-imager.sh     # download Raspberry Pi imager AppImage
./setup/disable-capslock.sh --install   # remap Caps Lock off (XDG autostart)
```
