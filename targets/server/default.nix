{
  environment.variables.EDITOR = "nvim";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 1w";
  };

  services.locate.enable = true;
  programs.nix-ld.enable = true;

  system.stateVersion = "25.05";

  imports = [
    ./config/boot.nix
    ./config/hardware-configuration.nix
    ./config/networking.nix
    ./config/packages.nix
    ./config/storage.nix
    ./config/users.nix
    ./config/virtualisation.nix
    ./services/btrfs-auto-snapshot.nix
    ./services/gpg-agent.nix
    ./services/sshd.nix
  ];
}
