# NixOS Configuration

Personal flake-based setup with two active targets:

- `server`: NixOS system + integrated Home Manager
- `mac`: standalone Home Manager profile for macOS

The root `flake.nix` is a small router that re-exports outputs from `envs/server` and `envs/mac`.
When evaluated from the repository root, dependency versions are pinned by the root `flake.lock`; the env flakes follow those root inputs.

## Structure

```text
.
├── assets/
│   └── nvim/                  # Shared Neovim config
├── envs/
│   ├── base/
│   │   └── home.d/            # Shared Home Manager defaults
│   ├── server/
│   │   ├── home.d/            # Server-only Home Manager modules
│   │   ├── os.d/              # NixOS modules
│   │   └── flake.nix
│   └── mac/
│       ├── home.d/            # macOS-only Home Manager modules
│       └── flake.nix
├── flake.nix
└── README.md
```

Both `home.d/modules` and `os.d/modules` are loaded dynamically (`*.nix`, sorted by filename).

## Managed Scope

- Server NixOS modules: boot, hardware, network, user, sshd, packages, cloudflared, gpg-agent, snapshot
- Shared Home Manager defaults: `git`, `ssh`, `zsh`, `nvim`, `direnv`, GC settings
- Server Home Manager modules: `tmux`
- macOS Home Manager modules: `zsh`, `kitty`, mac-specific packages/services
- Shared Neovim runtime in `assets/nvim`

## Common Commands

Run from repository root.

### Check / Evaluate

```bash
nix flake show
nix flake check
```

### Server (NixOS target)

```bash
sudo nixos-rebuild test --flake .#server
sudo nixos-rebuild switch --flake .#server
```

### macOS (Home Manager target)

```bash
home-manager build --flake .#mac
home-manager switch --flake .#mac
```

## Notes

- Both targets follow `nixpkgs` from `nixos-unstable`.
- `server` embeds Home Manager via `home-manager.nixosModules.home-manager`.
- `mac` is user-scoped only; it does not manage the full OS.
