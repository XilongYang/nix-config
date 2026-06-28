{ config, ... }:
{
  home.homeDirectory = "/Users/${config.home.username}";

  imports = [
    ../../shared/home-manager
    ./modules/gpg-agent.nix
    ./modules/kitty.nix
    ./modules/packages.nix
    ./modules/toggle-ime.nix
    ./modules/zsh.nix
  ];
}
