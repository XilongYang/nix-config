{ config, lib, pkgs, ... }:
let
  # Next to the Time Machine share, which is where the Apple devices on this
  # LAN already reach.
  dest = "/data/apple/podcasts";

  stateDir = "/var/lib/podcast-dl";

  # The publishers' own feeds, not the YouTube ones, whose enclosure is a
  # text/html embed with no audio behind it.
  #
  #   include    optional regex, re.search'd against the entry title
  #   maxPerRun  overrides --max-per-feed (3) for one feed
  #
  # Check a new entry with `sudo -u podcast-dl podcast-dl --dry-run` first.
  podcasts = [
    # Every NHK radio news programme in one feed, of which exactly one is wanted.
    {
      name = "nhk-myasa-0700";
      source = "NHKラジオニュース 午前7時";
      url = "https://www.nhk.or.jp/s-media/news/podcast/list/v1/all.xml";
      include = "マイあさ! 午前7時のNHKニュース";
    }
    { name = "tonari-no-zatsudan"; source = "となりの雑談";
      url = "https://feeds.megaphone.fm/TBS6714057012"; }
    { name = "nichiyou-tengoku"; source = "安住紳一郎の日曜天国";
      url = "https://feeds.megaphone.fm/TBS2679398439"; }
    # Their merged "Economist Podcasts" feed carries every show and several a day.
    { name = "economist-intelligence"; source = "The Intelligence";
      url = "https://access.acast.com/rss/d556eb54-6160-4c85-95f4-47d9f5216c49"; }
  ];

  podcastsFile = (pkgs.formats.json { }).generate "podcasts.json" podcasts;

  # The whole directory, so podcast-dl.py can import feedlib.py from beside it.
  rssSrc = ../../../files/server/rss;

  python = pkgs.python3.withPackages (ps: with ps; [ feedparser mutagen ]);

  # A named binary because every mode but the daily one is run by hand.
  podcast-dl = pkgs.writeShellScriptBin "podcast-dl" ''
    # Writing __pycache__ into the read-only store can only fail.
    export PYTHONDONTWRITEBYTECODE=1
    # The mode the unit gets from UMask=0002 below, for the runs by hand.
    umask 0002
    exec ${python}/bin/python3 ${rssSrc}/podcast-dl.py \
      --feeds ${podcastsFile} \
      --dest ${dest} \
      --state-dir ${stateDir} \
      "$@"
  '';
in
{
  users.users.podcast-dl = {
    isSystemUser = true;
    group = "podcast-dl";
    home = stateDir;
  };
  users.groups.podcast-dl = { };

  environment.systemPackages = [ podcast-dl ];

  systemd.tmpfiles.rules = [
    # setgid, group `users`: xilong can read the episodes and delete one here.
    "d ${dest} 2775 podcast-dl users -"
    # StateDirectory= would not create this until the unit's first 08:10.
    "d ${stateDir} 0750 podcast-dl podcast-dl -"
  ];

  systemd.services.podcast-dl = {
    description = "Fetch new podcast episodes into ${dest}";
    # After rss-digest at 08:00 rather than alongside it: 2 GB of RAM.
    startAt = "08:10";

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "podcast-dl";
      Group = "podcast-dl";
      StateDirectory = "podcast-dl";
      StateDirectoryMode = "0750";
      UMask = "0002";
      ExecStart = "${podcast-dl}/bin/podcast-dl";
      # A backlog of weekly shows at 40-75 MB an episode.
      TimeoutStartSec = 3600;

      # One file tree outside the state directory, and the network.
      ReadWritePaths = [ dest ];
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  # How the phone gets at the files, on a LAN-only port with no access control.
  services.static-web-server = {
    enable = true;
    listen = "[::]:8000";
    root = dest;
    configuration.general = {
      directory-listing = true;
      # 1 is name-descending, which given the date prefix puts the newest first.
      directory-listing-order = 1;
    };
  };

  # And for the Mac, read-only because the server prunes this on its own.
  services.samba.settings.Podcasts = {
    path = dest;
    "read only" = "yes";
    "valid users" = "xilong";
    "force user" = "xilong";
  };
}
