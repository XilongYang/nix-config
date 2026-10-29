{ config, lib, pkgs, ... }:
let
  # No source goes through RSSHub yet. When one does, add it to either group
  # below like any other feed -- the route list is at https://docs.rsshub.app
  #
  #   weibo = "${rsshub}/weibo/user/<uid>";
  #
  # goeland can only reach this because of the allow-loopback patch below.
  rsshub = "http://127.0.0.1:1200";

  stateDir = "/var/lib/goeland";

  # Read at runtime by goeland, so the app password never lands in the Nix
  # store. See the module comment below for how to create both secret files.
  passwordFile = "${stateDir}/smtp-password";

  # The addresses live outside the store too. goeland's config keys are all
  # overridable by environment, as GOELAND_<key with "." and "-" turned into
  # "_">, so systemd feeds them in from a file instead:
  #
  #   GOELAND_EMAIL_USERNAME           SMTP login (the Apple ID)
  #   GOELAND_PIPES_BLOGS_EMAIL_FROM   From: header, per-article mail
  #   GOELAND_PIPES_BLOGS_EMAIL_TO     To: header, per-article mail
  #   GOELAND_PIPES_NEWS_EMAIL_FROM    From: header, daily digest
  #   GOELAND_PIPES_NEWS_EMAIL_TO      To: header, daily digest
  #
  # The variable names embed the config key, so there is one pair per pipe.
  # Adding a feed to either group below needs no change here.
  environmentFile = "${stateDir}/env";
  unset = "unset@invalid";

  # Blogs: one message per new article, checked hourly. Every source needs
  # "unseen" or each run would re-send everything the window still covers.
  #
  # lasthours() is the first-run guard. A brand new source has nothing
  # recorded as seen, so without a window its whole backlog goes out one
  # message at a time. The extra hours leave slack for a missed run.
  blogs = {
    xilong = "https://xilong.site/atom.xml";
    stephenleng = "https://stephenleng.com/cn/feed";
    freemind = "https://freemind.pluskid.org/rss.xml";
  };
  blogFilters = [ "lasthours(26)" "unseen" ];

  # News: too high-volume for one mail per article, so these are rolled into
  # a single digest sent once a day. The window matches that cadence.
  #
  # Section headings in the digest come from each feed's own channel title,
  # which goeland takes verbatim and offers no way to override: the two FT
  # feeds call themselves "Technology" and "World" rather than naming FT.
  news = {
    ft-technology = "https://www.ft.com/technology?format=rss";
    ft-world = "https://www.ft.com/world?format=rss";
    hackernews = "https://news.ycombinator.com/rss";
  };
  newsFilters = [ "lasthours(24)" "unseen" ];

  feedSources = filters: lib.mapAttrs (_: url: {
    type = "feed";
    inherit url filters;
  });

  # Both runs share one config file and one database; each unit names the
  # single pipe it should execute. This is the module's own generated file:
  # same name and same content, so it is the same store path.
  confFile = (pkgs.formats.toml { }).generate "config.toml" config.services.goeland.settings;

  # The two timers collide every day at 08:00. goeland opens its "seen"
  # database with a one second lock timeout, and filterUnSeen treats a
  # failure to open it as "no filtering" rather than as an error -- so a
  # collision would re-send every article still inside the blog window, one
  # message each. Serialise the runs instead.
  run = pipe: "${pkgs.util-linux}/bin/flock ${stateDir}/lock ${pkgs.goeland}/bin/goeland run -c ${confFile} ${pipe}";
in
{
  # allow-loopback: goeland refuses to dial loopback and RFC1918 addresses
  #   (hardcoded SSRF guard in internal/goeland/httpget), which blocks reading
  #   from the RSSHub container on this host. Loopback only is re-allowed.
  #
  # subject-source-title: the subject template is handed the pipe's top-level
  #   source, so a single pipe over a merge source cannot name the blog an
  #   entry came from. Entries already carry a pointer to their own feed; the
  #   patch prefers it. That is what lets one pipe serve every blog, and so
  #   keeps the addresses down to one pair of variables per pipe.
  nixpkgs.overlays = [
    (final: prev: {
      goeland = prev.goeland.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../../../files/server/goeland/allow-loopback.patch
          ../../../files/server/goeland/subject-source-title.patch
        ];
      });
    })
  ];

  services.goeland = {
    enable = true;

    # This drives the blogs run only; the news digest has its own timer.
    schedule = "hourly";

    settings = {
      loglevel = "warning";
      auto-purge = true;
      purge-days = 30;

      # Space the fetches out rather than hitting every site at once.
      sleep-interval = "3s";

      email = {
        host = "smtp.mail.me.com";
        port = 587;
        username = unset; # GOELAND_EMAIL_USERNAME
        password_file = passwordFile;

        # The header is the goeland seagull logo plus an <h1>; the footer is a
        # "sent with love by goeland" line. Drop both.
        include-header = false;
        include-footer = false;
      };

      sources =
        feedSources blogFilters blogs
        // feedSources newsFilters news
        // {
          # No "digest" filter: the pipe sends one message per entry.
          blogs = {
            type = "merge";
            sources = lib.attrNames blogs;
          };
          # "digest" rolls every entry into a single message.
          news = {
            type = "merge";
            sources = lib.attrNames news;
            filters = [ "includesourcetitle" "includelink" "digest" ];
          };
        };

      pipes = {
        blogs = {
          source = "blogs";
          destination = "email";
          # Subject fields: EntryTitle, SourceTitle, SourceName, Today. Today
          # is the run time, not the article's own publication date.
          email_title = ''{{.Today.Format "2006-01-02 15:04"}} - {{.SourceTitle}} - {{.EntryTitle}}'';
          email_from = unset; # GOELAND_PIPES_BLOGS_EMAIL_FROM
          email_to = [ unset ]; # GOELAND_PIPES_BLOGS_EMAIL_TO
        };
        news = {
          source = "news";
          destination = "email";
          email_title = ''{{.Today.Format "2006-01-02"}} - News'';
          email_from = unset; # GOELAND_PIPES_NEWS_EMAIL_FROM
          email_to = [ unset ]; # GOELAND_PIPES_NEWS_EMAIL_TO
        };
      };
    };
  };

  # Both secret files are created by hand, once, and never by Nix:
  #
  #   sudo install -d -o goeland -g goeland -m 0750 /var/lib/goeland
  #   printf '%s' 'xxxx-xxxx-xxxx-xxxx' \
  #     | sudo install -o goeland -g goeland -m 0400 /dev/stdin \
  #       /var/lib/goeland/smtp-password
  #   sudo install -o goeland -g goeland -m 0400 /dev/stdin \
  #       /var/lib/goeland/env <<'EOF'
  #   GOELAND_EMAIL_USERNAME="you@icloud.com"
  #   GOELAND_PIPES_BLOGS_EMAIL_FROM="RSS Subscription <rss@example.com>"
  #   GOELAND_PIPES_BLOGS_EMAIL_TO="rss@example.com"
  #   GOELAND_PIPES_NEWS_EMAIL_FROM="RSS Subscription <rss@example.com>"
  #   GOELAND_PIPES_NEWS_EMAIL_TO="rss@example.com"
  #   EOF
  #
  # Quote the values: systemd parses them fine either way, but the angle
  # brackets in From make an unquoted file impossible to source from a shell.
  # No "-" prefix on EnvironmentFile: a missing file should fail the unit
  # rather than let it mail the placeholder addresses.
  systemd.services.goeland = {
    # goeland reaches RSSHub over loopback, so it needs the container running
    # before it starts for any RSSHub-backed source to resolve.
    after = [ "podman-rsshub.service" ];
    wants = [ "podman-rsshub.service" ];

    serviceConfig.EnvironmentFile = environmentFile;
    # The module's own ExecStart runs every pipe; restrict it to the blogs.
    serviceConfig.ExecStart = lib.mkForce (run "blogs");
  };

  systemd.services.goeland-news = {
    description = "goeland news digest";
    startAt = "08:00";

    after = [ "podman-rsshub.service" "goeland.service" ];
    wants = [ "podman-rsshub.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "goeland";
      Group = "goeland";
      StateDirectory = "goeland";
      StateDirectoryMode = "0750";
      EnvironmentFile = environmentFile;
      ExecStart = run "news";
    };
  };
}
