# Habitus — Agent Instructions

## This Repo Is Public

habitus is published on GitHub. Everything committed is public: file contents
**and commit messages**. Rewriting history later doesn't reach existing clones
or forks. The config is meant to work on anyone's machine, so nothing about the
owner's own environment needs to be in it.

Never write any of these into a tracked file or a commit message:

- The owner's machines: hostnames, nicknames, and exact hardware models,
  including in benchmark notes (e.g. "on bigbox", "the ThinkPad", "a Ryzen 7
  5800X", "an RX 6800"). Give the class instead: "a 4-core AVX2 laptop CPU",
  "a mid-range consumer GPU", "16 GB of RAM".
- The owner's other repos, private tools, or projects, including a sibling repo
  you borrowed a test container from, and references to their todos or journal.
- Personal paths (`/home/<user>/…`, a private repo's checkout), usernames,
  IP addresses, internal hostnames/URLs, ports of self-hosted services, ssh
  host aliases.

Describe the *condition*, not the machine: "a Wayland session with only xsel
installed", "a 4-core AVX2 laptop CPU", "a remote host over ssh", "a throwaway
container". Public upstream projects (`ggml-org/llama.cpp`, plugin repos),
generic paths (`~/.local/bin`, `$HOME`), and placeholders
(`http://<host>:<port>`) are fine.

Machine-specific values (a server URL, a model name, a host) belong in
`shell/local.d/` (gitignored); tracked code reads them from the environment
and has no personal default.

Some older commits in `git log` name machines and private tools. They predate
this rule: read them for format only, and never reuse their text. If a file
you're editing already contains such a detail, replace it rather than keep it.

Before committing, list every name in the message and the added lines: hosts,
machines, hardware, repos, tools, paths, people. Each must be a public project,
something in this repo, or a generic term. Anything you only know from this
session, the owner's other files, or their other tools goes, even if it came
from the user or an old commit. If the user asks you to include such a detail,
remind them the repo is public, offer a place that isn't (`shell/local.d/`,
their own notes), and include it only if they confirm.

This applies only to what gets committed; you can talk about their machines
normally in conversation.

## Do Not Modify

- **`shell/init.sh`**: unless changing the loading mechanism itself.
- **`shell/install.sh`** (the orchestrator) and **`shell/install.d/_lib.sh`**:
  unless changing the install/uninstall mechanism itself. Numbered step files
  in `install.d/` are normal editable code.
