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

Then open a new terminal. `install.sh` runs the steps in `shell/install.d/` in
order; each one says what it does in its header. It never uses sudo: when a
step is missing a system package, it warns and prints how to install it.

Re-run `./shell/install.sh` after a `git pull` to update, and
`./shell/install.sh --uninstall` to remove everything it set up.

## Per-machine config

Shell files in `shell/local.d/*.sh` are gitignored and sourced after the topic
files, so machine-specific settings (hosts, server URLs, model names) go there.

## Optional installers

`setup/` holds scripts that `install.sh` doesn't run, for things that need
root or aren't wanted everywhere. Each says what it does in its header.
