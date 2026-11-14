{ config, ... }:
{
  home.homeDirectory = "/Users/${config.home.username}";

  home.sessionPath = [
    "$HOME/.nix-profile/bin"
    "/nix/var/nix/profiles/default/bin"
  ];

  imports = [
    ../../shared/home-manager
    ./modules/gpg-agent.nix
    ./modules/jpime.nix
    ./modules/karabiner.nix
    ./modules/kitty.nix
    ./modules/packages.nix
    ./modules/zsh.nix
  ];
}
