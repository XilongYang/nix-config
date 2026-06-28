# NixOS Configuration

Personal flake-based setup with two active targets:

- `server`: NixOS system + integrated Home Manager
- `mac`: standalone Home Manager profile for macOS

The root `flake.nix` is a small router that re-exports outputs from `envs/server` and `envs/mac`.
Dependency versions are pinned by the single root `flake.lock`; the env flakes follow those root inputs.

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
- Shared Home Manager defaults: `git`, `ssh`, `zsh`, `nvim`, GC settings
- Server Home Manager modules: `tmux`
- macOS Home Manager modules: `zsh`, `kitty`, mac-specific packages/services
- Shared Neovim runtime in `assets/nvim`

## Common Commands

Run from repository root.

### Server

Check configuration:

```bash
nix flake show
nix flake check
sudo nixos-rebuild test --flake .#server
```

Apply the currently pinned versions in `flake.lock`:

```bash
sudo nixos-rebuild switch --flake .#server
```

Upgrade inputs, then apply them:

```bash
nix flake update
sudo nixos-rebuild switch --flake .#server
```

### macOS

Check configuration:

```bash
nix flake show
nix flake check
home-manager build --flake .#mac
```

Apply the currently pinned versions in `flake.lock`:

```bash
home-manager switch --flake .#mac
```

Upgrade inputs, then apply them:

```bash
nix flake update
home-manager switch --flake .#mac
```

## Notes

- From the repository root, `server` and `mac` use the same pinned input revisions from the root `flake.lock`, including the same `nixpkgs` and `home-manager` versions.
- They do not produce the same package set byte-for-byte: `server` builds for `x86_64-linux`, `mac` builds for `aarch64-darwin`, and `server` also includes the `kiln` input.
- `envs/server` and `envs/mac` are implementation details of the root flake. Update and switch commands should be run from the repository root.
- Both targets follow `nixpkgs` from `nixos-unstable`.
- `server` embeds Home Manager via `home-manager.nixosModules.home-manager`.
- `mac` is user-scoped only; it does not manage the full OS.
