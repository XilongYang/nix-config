{ pkgs, ... }:
let
  commonPkgs = import ../../../shared/common-pkgs.nix { inherit pkgs; };
in
{
  home.packages = commonPkgs ++ (with pkgs; [
    coreutils
    macism
    pinentry_mac
  ]);
}
