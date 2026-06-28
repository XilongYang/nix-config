# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, lib, ... }:
let
  dir = ./modules;
  entries = if builtins.pathExists dir then builtins.readDir dir else {};
  names = builtins.filter (name:
    entries.${name} == "regular" && lib.hasSuffix ".nix" name
  ) (builtins.attrNames entries);
  sorted = lib.sort (a: b: a < b) names;
in

{
  environment.variables.EDITOR = "nvim";
  # `enableAllTerminfo` currently pulls in `termite`, which fails to build via
  # `vte` on the pinned nixpkgs revision. Keep a narrow set of terminal entries
  # that are actually useful for remote sessions instead.
  environment.systemPackages = with pkgs; [
    kitty.terminfo
    tmux.terminfo
  ];

  # Use the Nix-Flakes and nix-command
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # NixOS GC
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 1w";
  };

  # Enable the locate & updatedb
  services.locate.enable = true;

  # Enable nix-ld
  programs.nix-ld.enable = true;

  imports = builtins.map (name: dir + "/${name}") sorted;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
