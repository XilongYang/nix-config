{ pkgs, ... }:
{
  programs.zsh.enable = true;

  users.users.xilong = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" ];
    shell = pkgs.zsh;
  };

  nix.settings.trusted-users = [ "xilong" ];
}
