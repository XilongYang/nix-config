# NixOS Configuration

Single-flake personal setup with two targets:

- `server`: NixOS system with integrated Home Manager
- `mac`: standalone Home Manager profile for macOS

## Layout

The repository is split by responsibility:

- `targets/`: concrete deployment targets (Nix logic)
- `shared/`: reusable Nix modules and packages
- `files/`: raw, non-Nix source files (config and scripts) referenced by the modules

```text
.
├── targets/
│   ├── mac/
│   │   ├── default.nix
│   │   └── modules/
│   └── server/
│       ├── default.nix
│       ├── config/
│       ├── home-manager/
│       └── services/
├── shared/
│   ├── common-pkgs.nix
│   └── home-manager/
│       ├── default.nix
│       └── modules/
├── files/
│   ├── mac/
│   │   ├── jpime/jpime.swift
│   │   ├── karabiner/karabiner.json
│   │   └── kitty/kitty-nvim-ime.py
│   ├── server/
│   │   └── rss/
│   └── shared/
│       └── nvim/
├── flake.nix
└── README.md
```

`files/` mirrors the `mac` / `server` / `shared` scoping of the Nix tree. It holds
verbatim source in its native language — dotfiles that land in `~/.config`
(nvim, karabiner) as well as patches and scripts that Nix reads in as build
inputs — so each file can be edited, highlighted, and linted on its own instead
of living inside a Nix string.

## Entrypoints

- `server` resolves from `targets/server`
- `mac` resolves from `targets/mac`
- shared Home Manager defaults resolve from `shared/home-manager`

`flake.nix` wires only the top-level targets:

- `nixosConfigurations.server`
- `homeConfigurations.mac`

## Target Roles

- `targets/server/default.nix` assembles the NixOS machine
- `targets/server/config/` holds machine-local configuration such as boot, networking, packages, users, and storage
- `targets/server/services/` holds server-only NixOS service modules
- RSS never sends mail: `services/rss-digest.nix` fetches the feeds, builds one brief, has Claude edit it, and puts the result straight into the mailbox with an IMAP `APPEND`. The model is optional -- when it is unavailable the unedited brief is delivered with a line at the top saying so.
- Audio never goes through the mail: `services/podcast-dl.nix` pulls podcast enclosures into `/data/apple/podcasts` byte for byte, tags them, and prunes them after 30 days. The files are read off a directory listing on `:8000` (LAN only, no access control) or the read-only `Podcasts` SMB share. It needs no credentials of any kind.
- `targets/server/home-manager/` holds the Home Manager entry for the server user plus server-only modules
- `targets/mac/default.nix` assembles the macOS Home Manager profile
- `targets/mac/modules/` holds mac-only Home Manager modules

## Shared Roles

- `shared/home-manager/default.nix` imports the common Home Manager modules
- `shared/home-manager/modules/` contains shared `git`, `ssh`, `zsh`, `nvim`, `gnupg`, `npm`, and base settings
- `shared/common-pkgs.nix` contains shared development packages

## Source Files

- `files/shared/nvim/` holds the Neovim runtime (`init.lua`, `lua/`, `lsp/`) symlinked into Home Manager by `shared/home-manager/modules/nvim.nix`
- `files/mac/` holds mac-only source: the Karabiner config, the kitty IME watcher, and `jpime/jpime.swift`, a Carbon TIS CLI that toggles the Japanese input method on and off (⌃⌥J via Karabiner). `targets/mac/modules/jpime.nix` compiles it to `~/.local/bin/jpime` on activation with the system `swiftc`, so that step needs Xcode Command Line Tools and is the one non-Nix dependency of the mac target
- `files/server/rss/` holds two delivery paths over one feed layer. `digest.py`, driven by `targets/server/services/rss-digest.nix`, is the IMAP digest pipeline (fetch, brief, model, render, `APPEND`, each stage checkpointed so a failed run is re-runnable without spending the model's quota twice), with `schema.json` (the digest structure, enforced by `claude --json-schema`), `prompt.md` (the editing instructions, passed as `--system-prompt-file` so the built-in agent prompt is replaced rather than appended to), and `templates/` (`mail.html.j2` and `mail.txt.j2`, which own the mail's appearance -- edit these to restyle it, `digest.py` holds no markup). `podcast-dl.py`, driven by `services/podcast-dl.nix`, is the audio path: newest-first, one episode at a time, committing the seen-state per file. `feedlib.py` is the half they share -- fetching a feed, deciding which entries are new, remembering what was delivered -- and both scripts are referenced through the directory rather than the file so that import works without a `PYTHONPATH`
- Modules pull these in via `builtins.readFile` / store-path references, substituting any Nix values through `@placeholder@` tokens so no import-from-derivation is needed

## Commands

Run from the repository root.

### Server

```bash
nix flake show
nix flake check
sudo nixos-rebuild test --flake .#server
sudo nixos-rebuild switch --flake .#server
```

### macOS

```bash
nix flake show
nix flake check
home-manager build --flake .#mac
home-manager switch --flake .#mac
```

### Update Inputs

```bash
nix flake update
```

Then re-apply the target you care about.

## Notes

- Both targets share the same root `flake.lock`
- `nixpkgs` tracks `nixos-unstable`, and `home-manager` tracks `master` to keep the macOS and NixOS module surface aligned
- `server` uses `x86_64-linux`
- `mac` uses `aarch64-darwin`
- Neovim plugin management is intentionally split: Nix distributes the config in `files/shared/nvim/`, while `lazy.nvim` resolves and downloads plugins at runtime
