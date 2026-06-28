{ pkgs, ... }:
{
  programs.zsh.enable = true;

  users.users.xilong = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    shell = pkgs.zsh;
  };

  nix.settings.trusted-users = [ "xilong" ];
}
