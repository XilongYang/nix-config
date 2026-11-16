{ config, lib, pkgs, ... }:
let
  # Where the episodes land, and the only thing in this module that anything
  # else sees. It sits under /data/apple next to the Time Machine share because
  # that is already the directory the Apple devices on this LAN reach for.
  dest = "/data/apple/podcasts";

  stateDir = "/var/lib/podcast-dl";

  # Audio only, so every entry needs a real enclosure. The three TBS/Economist
  # shows were reached through YouTube playlists first; those feeds carry a
  # text/html embed as their enclosure and no file at all, so the publishers'
  # own feeds are used instead -- megaphone and Acast, found through the iTunes
  # podcast directory.
  #
  #   include    optional regex, re.search'd against the entry title. The
  #              entries it does not match are treated as though the feed had
  #              never carried them, and are never recorded as seen.
  #   maxPerRun  overrides --max-per-feed (3) for one feed.
  #
  # Check a new entry with `sudo -u podcast-dl podcast-dl --dry-run` before the
  # first real run: it prints the episodes the regex selects and the file names
  # they would get, and downloads nothing.
  podcasts = [
    # One feed carrying every NHK radio news programme -- hourly bulletins,
    # 正午, ジャーナル, and マイあさ! at 5, 6, 7 and 8 -- of which exactly one
    # is wanted. 156 entries on the day this was written, 7 of them matching.
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
    # The Economist's daily programme. Their merged "Economist Podcasts" feed
    # carries every show they publish and more than one episode a day, which is
    # a different thing to want; it is
    # https://access.acast.com/rss/ec380acc-fe13-46a0-991f-a1e508d126f8
    { name = "economist-intelligence"; source = "The Intelligence";
      url = "https://access.acast.com/rss/d556eb54-6160-4c85-95f4-47d9f5216c49"; }
  ];

  podcastsFile = (pkgs.formats.json { }).generate "podcasts.json" podcasts;

  # The whole directory, not each file, so that podcast-dl.py can import
  # feedlib.py from beside itself -- Python puts a script's own directory on
  # sys.path, which needs no PYTHONPATH as long as the two share a store path.
  rssSrc = ../../../files/server/rss;

  python = pkgs.python3.withPackages (ps: with ps; [ feedparser mutagen ]);

  # A named binary because every mode but the daily one is run by hand:
  # --dry-run when adding a show, --forget to re-fetch an episode, --seed-state
  # to skip a backlog.
  podcast-dl = pkgs.writeShellScriptBin "podcast-dl" ''
    # The script lives in the read-only store, where writing __pycache__ can
    # only fail; Python would ignore that silently, but not attempting it is
    # tidier.
    export PYTHONDONTWRITEBYTECODE=1
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

  # setgid, group `users`: new files and show directories inherit that group
  # regardless of which group the unit runs as, and with the unit's UMask=0002
  # they come out group-writable. So xilong -- whose primary group this is --
  # can read them over SMB and delete one after importing it.
  systemd.tmpfiles.rules = [
    "d ${dest} 2775 podcast-dl users -"
  ];

  systemd.services.podcast-dl = {
    description = "Fetch new podcast episodes into ${dest}";
    # After rss-digest at 08:00 rather than alongside it: this machine has 2 GB
    # of RAM and no reason to run both at once. The one time-critical feed is
    # NHK's 07:20 bulletin, which is out well before this.
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
      # A backlog of weekly shows at 40-75 MB an episode, over whatever the
      # line gives that morning.
      TimeoutStartSec = 3600;

      # One file tree outside the state directory, and the network. Note that
      # unlike rss-digest this unit needs no credentials at all: no
      # EnvironmentFile, nothing to leak.
      ReadWritePaths = [ dest ];
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  # How the phone gets at the files: a directory listing on the port that is
  # already open in the firewall. Reachable from the LAN and nowhere else --
  # nothing here is exposed to the internet, and the listing has no access
  # control, so everything on the LAN can read it.
  services.static-web-server = {
    enable = true;
    listen = "[::]:8000";
    root = dest;
    configuration.general = {
      directory-listing = true;
      # 1 is "name descending", which given the YYYY-MM-DD prefix puts the
      # newest episode of a show at the top of the list -- the one you came
      # for, without scrolling, on a phone. The default is unordered.
      directory-listing-order = 1;
    };
  };

  # And for the Mac when it happens to be on. Read-only: the server owns this
  # directory's contents and prunes them on its own schedule.
  services.samba.settings.Podcasts = {
    path = dest;
    "read only" = "yes";
    "valid users" = "xilong";
    "force user" = "xilong";
  };
}
