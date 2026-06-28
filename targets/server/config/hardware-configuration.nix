{ lib, ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
    fsType = "btrfs";
    options = [ "subvol=@,compress=zstd,ssd,space_cache=v2,discard=async,noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
    fsType = "btrfs";
    options = [ "subvol=@home,compress=zstd,ssd,space_cache=v2,discard=async,noatime" ];
  };

  fileSystems."/home/xilong/.cache" = {
    device = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
    fsType = "btrfs";
    options = [ "subvol=@home_cache,compress=zstd,ssd,space_cache=v2,discard=async,noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
    fsType = "btrfs";
    options = [ "subvol=@nix,compress=zstd,ssd,space_cache=v2,discard=async,noatime" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
    fsType = "btrfs";
    options = [ "subvol=@var_log,compress=zstd,ssd,space_cache=v2,discard=async,noatime" ];
  };

  fileSystems."/var/cache" = {
    device = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
    fsType = "btrfs";
    options = [ "subvol=@var_cache,compress=zstd,ssd,space_cache=v2,discard=async,noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/ADB9-3884";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
