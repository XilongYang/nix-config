{ config, pkgs, ... }:
{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    # Base
    curl
    git
    git-filter-repo
    gnupg
    openssh
    openssl
    pass
    pinentry-curses
    ripgrep
    tree
    tmux
    zsh

    # Application
    bash-language-server
    neovim
    nixd
    nodejs
    codex
    codex-acp
  ];
}
