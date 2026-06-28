{ pkgs, ... }:
let
  commonPkgs = import ../../../shared/common-pkgs.nix { inherit pkgs; };
in
{
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = commonPkgs ++ (with pkgs; [
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
    nodejs
    kiln
    bubblewrap
    kitty.terminfo
    tmux.terminfo
  ]);
}
