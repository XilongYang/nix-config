{ config, pkgs, ... }:
let
  commonPackages = import ../../../base/common-packages.nix { inherit pkgs; };
in
{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = commonPackages ++ (with pkgs; [
    # Base
    curl
    git-filter-repo
    gnupg
    openssh
    openssl
    pass
    pinentry-curses
    python3
    tree
    tmux
    zsh

    # Application
    nodejs
    kiln

    # CodeX Dependencies
    bubblewrap

  ]);
}
