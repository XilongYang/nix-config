{ config, ... }:
{
  home.homeDirectory = "/home/${config.home.username}";

  imports = [
    ../../../shared/home-manager
    ./modules/tmux.nix
  ];
}
