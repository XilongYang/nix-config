{ config, pkgs, lib, ... }:
let
  dir = ./modules;
  entries = if builtins.pathExists dir then builtins.readDir dir else {};
  names = builtins.filter (name:
    entries.${name} == "regular" && lib.hasSuffix ".nix" name
  ) (builtins.attrNames entries);
  sorted = lib.sort (a: b: a < b) names;
  commonPackages = import ../../base/common-packages.nix { inherit pkgs; };
in
{
  home.homeDirectory = "/Users/${config.home.username}";
  home.stateVersion = "23.11";
  programs.home-manager.enable = true;

  imports = builtins.map (name: dir + "/${name}") sorted;

  home.packages = commonPackages ++ (with pkgs; [
    coreutils
    macism
    pinentry_mac
  ]);

  # macOS 上 GPG agent 走 pinentry-mac
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry_mac;
    defaultCacheTtl = 86400;
    maxCacheTtl = 604800;
  };
}
