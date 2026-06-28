{ config, pkgs, lib, ... }:
let
  cfg = config.service.btrfsAutoSnapshot;

  snapshotAges = [
    3600
    7200
    10800
    43200
    86400
    259200
    604800
    2592000
    7776000
    15552000
  ];

  snapshotScript = pkgs.writeShellScript "btrfs-auto-snapshot" ''
    set -euo pipefail

    ROOT=/mnt/btrfs-root
    SNAPDIR=".snapshots"
    NOW=$(date +%s)

    mkdir -p "$ROOT"
    mount -o subvolid=5 ${cfg.device} "$ROOT"
    mkdir -p "$ROOT/$SNAPDIR"

    ts=$(date +"%Y-%m-%dT%H:%M:%S")

    btrfs subvolume snapshot -r "$ROOT/@" "$ROOT/$SNAPDIR/@-$ts"
    btrfs subvolume snapshot -r "$ROOT/@home" "$ROOT/$SNAPDIR/@home-$ts"

    snapshots=$(ls "$ROOT/$SNAPDIR" | grep '^@-' | sed 's/^@-//')

    for age in ${toString snapshotAges}; do
      target=$((NOW - age))
      candidate=""
      candidate_ts=0

      for s in $snapshots; do
        t=$(date -d "$s" +%s || true)
        if [ "$t" -le "$target" ] && [ "$t" -gt "$candidate_ts" ]; then
          candidate="$s"
          candidate_ts="$t"
        fi
      done

      for s in $snapshots; do
        [ "$s" = "$candidate" ] && continue
        t=$(date -d "$s" +%s || true)
        if [ "$t" -le "$target" ]; then
          btrfs subvolume delete "$ROOT/$SNAPDIR/@-$s" 2>/dev/null || true
          btrfs subvolume delete "$ROOT/$SNAPDIR/@home-$s" 2>/dev/null || true
        fi
      done
    done

    umount "$ROOT"
  '';
in
{
  options.service.btrfsAutoSnapshot = {
    enable = lib.mkEnableOption "Btrfs automatic snapshots (@ and @home)";

    device = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
      description = "Block device path used for snapshot.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.btrfs-auto-snapshot = {
      description = "Btrfs automatic snapshots (@ and @home)";
      serviceConfig.Type = "oneshot";

      path = with pkgs; [
        btrfs-progs
        coreutils
        util-linux
        gawk
      ];

      script = ''
        exec ${snapshotScript}
      '';
    };

    systemd.timers.btrfs-auto-snapshot = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
}
