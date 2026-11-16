{ config, lib, pkgs, ... }:
let
  stateDir = "/var/lib/rss-digest";

  # Read at runtime so no secret lands in the Nix store; created by hand below.
  environmentFile = "${stateDir}/env";

  # "blogs" are followed deliberately, "news" is a firehose to filter -- the
  # model is handed the group and treats the two differently, see prompt.md.
  feeds = [
    { name = "xilong"; group = "blogs"; url = "https://xilong.site/atom.xml"; }
    { name = "stephenleng"; group = "blogs"; url = "https://stephenleng.com/cn/feed"; }
    { name = "freemind"; group = "blogs"; url = "https://freemind.pluskid.org/rss.xml"; }
    # Both FT feeds title themselves by section rather than paper, so "source"
    # overrides it.
    { name = "ft-technology"; group = "news"; source = "FT"; url = "https://www.ft.com/technology?format=rss"; }
    { name = "ft-world"; group = "news"; source = "FT"; url = "https://www.ft.com/world?format=rss"; }
    { name = "hackernews"; group = "news"; url = "https://news.ycombinator.com/rss"; }
  ];

  feedsFile = (pkgs.formats.json { }).generate "feeds.json" feeds;

  # The whole directory, so digest.py can import feedlib.py from beside it.
  rssSrc = ../../../files/server/rss;

  schemaFile = "${rssSrc}/schema.json";
  promptFile = "${rssSrc}/prompt.md";

  # The mail's whole appearance, the only contract being the set of fields that
  # mail.html.j2 documents at its top.
  templateDir = "${rssSrc}/templates";

  python = pkgs.python3.withPackages (ps: with ps; [ feedparser html2text jinja2 ]);

  # Every step is checkpointed under ${stateDir}/runs/<date>/, so a failed run
  # can simply be re-run without paying for the model twice.
  #
  # The model is the one stage allowed to be missing: the brief then goes out
  # unedited with a line at the top saying why.
  #
  # A named binary because every mode but the daily one is run by hand, with
  # HOME and the working directory set here so both behave alike.
  digest = pkgs.writeShellScriptBin "rss-digest" ''
    export HOME=${stateDir}
    export CLAUDE_CONFIG_DIR=${stateDir}/claude
    cd ${stateDir}
    export PYTHONDONTWRITEBYTECODE=1
    exec ${python}/bin/python3 ${rssSrc}/digest.py \
      --feeds ${feedsFile} \
      --schema ${schemaFile} \
      --prompt ${promptFile} \
      --template-dir ${templateDir} \
      --state-dir ${stateDir} \
      --model sonnet \
      --max-budget 2 \
      "$@"
  '';
in
{
  users.users.rss-digest = {
    isSystemUser = true;
    group = "rss-digest";
    home = stateDir;
  };
  users.groups.rss-digest = { };

  # On PATH for the hand-run modes: `sudo -u rss-digest rss-digest --no-model`.
  environment.systemPackages = [ digest ];

  systemd.services.rss-digest = {
    description = "RSS digest, edited by Claude, delivered by IMAP APPEND";
    startAt = "08:00";

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # --bare would isolate claude further but takes no subscription token.
    path = [ pkgs.claude-code ];

    serviceConfig = {
      Type = "oneshot";
      User = "rss-digest";
      Group = "rss-digest";
      StateDirectory = "rss-digest";
      StateDirectoryMode = "0750";
      WorkingDirectory = stateDir;
      # No "-" prefix: a missing file should fail the unit, not run blind.
      EnvironmentFile = environmentFile;
      ExecStart = "${digest}/bin/rss-digest";

      # A small blast radius for a model prompt built from untrusted feeds.
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  # The environment file is created by hand, once, after the first rebuild --
  # the rss-digest user does not exist before it.
  #
  #   sudo install -d -o rss-digest -g rss-digest -m 0750 /var/lib/rss-digest
  #   sudo install -o rss-digest -g rss-digest -m 0400 /dev/stdin \
  #       /var/lib/rss-digest/env <<'EOF'
  #   RSS_IMAP_HOST="imap.mail.me.com"
  #   RSS_IMAP_USER="you@icloud.com"
  #   RSS_IMAP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
  #   RSS_IMAP_FOLDER="RSS"
  #   RSS_MAIL_FROM="RSS Digest <rss@example.com>"
  #   RSS_MAIL_TO="rss@example.com"
  #   CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-..."
  #   EOF
  #
  # RSS_IMAP_FOLDER must be top-level: iCloud takes no children under INBOX.
  # The password is an app-specific one.
  #
  # The token comes from `claude setup-token` on a machine already signed in to
  # the subscription, and the unit fails loudly once it expires.
  #
  # It spends the same quota as interactive use, hence sonnet and not opus.
  #
  # The first run would otherwise digest every backlog, so deliver it once
  # unedited -- which also checks the IMAP side and spends no quota:
  #
  #   sudo -u rss-digest rss-digest --no-model
  #
  # Or throw that backlog away instead of reading it:
  #
  #   sudo -u rss-digest rss-digest --seed-state
  #
  # And the inverse, undoing a delivery for every feed or only the ones named:
  #
  #   sudo -u rss-digest rss-digest --forget
  #   sudo -u rss-digest rss-digest --forget hackernews ft-world
}
