# NixOS Configuration

Single-flake personal setup with two targets:

- `server`: NixOS system with integrated Home Manager
- `mac`: standalone Home Manager profile for macOS

## Layout

The repository is split by responsibility:

- `targets/`: concrete deployment targets
- `shared/`: reusable modules, packages, and Neovim runtime

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
│   ├── home-manager/
│   │   ├── default.nix
│   │   └── modules/
│   └── nvim/
├── flake.nix
└── README.md
```

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
- `targets/server/home-manager/` holds the Home Manager entry for the server user plus server-only modules
- `targets/mac/default.nix` assembles the macOS Home Manager profile
- `targets/mac/modules/` holds mac-only Home Manager modules

## Shared Roles

- `shared/home-manager/default.nix` imports the common Home Manager modules
- `shared/home-manager/modules/` contains shared `git`, `ssh`, `zsh`, `nvim`, and base settings
- `shared/common-pkgs.nix` contains shared development packages
- `shared/nvim/` contains the Neovim runtime synced into Home Manager

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
- `server` uses `x86_64-linux`
- `mac` uses `aarch64-darwin`
- `server` applies the `kiln` overlay
