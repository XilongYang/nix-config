{ config, lib, pkgs, ... }:
let
  # No source goes through RSSHub yet. When one does, add it below like any
  # other feed -- the route list is at https://docs.rsshub.app
  #
  #   { name = "weibo"; group = "news"; url = "${rsshub}/weibo/user/<uid>"; }
  #
  # Nothing in this pipeline refuses to dial loopback, so reaching the
  # container takes no patched fetcher.
  rsshub = "http://127.0.0.1:1200";

  stateDir = "/var/lib/rss-digest";

  # Secrets and addresses are read at runtime, so neither the iCloud app
  # password nor the mail addresses land in the Nix store. See the comment at
  # the bottom for how to create the file.
  environmentFile = "${stateDir}/env";

  # "blogs" are people the reader follows deliberately; "news" is a firehose to
  # be filtered. The group is handed to the model, which treats the two
  # differently -- see prompt.md. It is the only thing the group does: both
  # groups land in one digest.
  feeds = [
    { name = "xilong"; group = "blogs"; url = "https://xilong.site/atom.xml"; }
    { name = "stephenleng"; group = "blogs"; url = "https://stephenleng.com/cn/feed"; }
    { name = "freemind"; group = "blogs"; url = "https://freemind.pluskid.org/rss.xml"; }
    # Both FT feeds name their section in the channel title -- "Technology"
    # and "World" -- rather than the paper, so "source" overrides it. Without
    # that the model cannot tell the two apart from any other outlet, and a
    # merged story ends up labelled "Technology · World · World".
    { name = "ft-technology"; group = "news"; source = "FT"; url = "https://www.ft.com/technology?format=rss"; }
    { name = "ft-world"; group = "news"; source = "FT"; url = "https://www.ft.com/world?format=rss"; }
    { name = "hackernews"; group = "news"; url = "https://news.ycombinator.com/rss"; }
  ];

  feedsFile = (pkgs.formats.json { }).generate "feeds.json" feeds;
  schemaFile = ../../../files/server/rss/schema.json;
  promptFile = ../../../files/server/rss/prompt.md;

  # The mail's appearance lives entirely in these two Jinja templates --
  # mail.html.j2 and mail.txt.j2 -- and digest.py never looks inside them. Edit
  # them to restyle the brief; the only contract is the set of fields, which
  # mail.html.j2 documents at the top. They render both the edited digest and
  # the unedited brief, so a change cannot leave the fallback mail behind.
  templateDir = ../../../files/server/rss/templates;

  python = pkgs.python3.withPackages (ps: with ps; [ feedparser html2text jinja2 ]);

  # The script fetches, builds a brief by rule, lets the model edit it, renders
  # it and APPENDs it, checkpointing each step in ${stateDir}/runs/<date>/ and
  # committing the seen-state only after the APPEND is acknowledged. So a
  # failed run can simply be re-run: `systemctl start rss-digest` picks up
  # where it stopped and does not spend the model's quota twice.
  #
  # The model is the one stage that is allowed to be missing. Rate-limited,
  # expired token, timed out, bad output: the brief goes out as it stands with
  # a line at the top saying why it was not edited, and that failure is not
  # checkpointed, so a re-run gets another attempt. `--no-model` forces that
  # path, which is also the way to see what the brief looks like on its own.
  # A named binary rather than a bare store path, because every mode but the
  # daily one is run by hand: seeding the state, re-running a failed delivery,
  # looking at the brief with --no-model. HOME and CLAUDE_CONFIG_DIR are set
  # here and not on the unit so that a hand-run and the timer behave alike --
  # claude keeps its state under $HOME and reads CLAUDE.md from the working
  # directory, and neither should ever reach outside the state directory.
  digest = pkgs.writeShellScriptBin "rss-digest" ''
    export HOME=${stateDir}
    export CLAUDE_CONFIG_DIR=${stateDir}/claude
    cd ${stateDir}
    exec ${python}/bin/python3 ${../../../files/server/rss/digest.py} \
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

    # RSSHub only matters once a feed above points at it, but starting after it
    # costs nothing and saves a confusing first failure when one does.
    after = [ "network-online.target" "podman-rsshub.service" ];
    wants = [ "network-online.target" "podman-rsshub.service" ];

    # --bare would isolate claude more thoroughly, but it refuses to read
    # anything but ANTHROPIC_API_KEY / apiKeyHelper -- never a subscription
    # token -- so it is unusable here. The HOME, CLAUDE_CONFIG_DIR and working
    # directory the wrapper sets cover the same ground for this unit.
    path = [ pkgs.claude-code ];

    serviceConfig = {
      Type = "oneshot";
      User = "rss-digest";
      Group = "rss-digest";
      StateDirectory = "rss-digest";
      StateDirectoryMode = "0750";
      WorkingDirectory = stateDir;
      # No "-" prefix: a missing file should fail the unit rather than let it
      # run with no credentials and no idea where to deliver.
      EnvironmentFile = environmentFile;
      ExecStart = "${digest}/bin/rss-digest";

      # One daily shot at the network and one file tree. Nothing here needs
      # more, and the unit runs a model with a prompt assembled from untrusted
      # feed content, so the blast radius is worth keeping small.
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  # The environment file is created by hand, once, and never by Nix. It has to
  # come after the first rebuild: the rss-digest user does not exist until then
  # and StateDirectory= only creates the directory when the unit first runs.
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
  # RSS_IMAP_FOLDER must be a top-level mailbox: iCloud does not take children
  # under INBOX. The password is an app-specific password, the same kind the
  # old SMTP path used.
  #
  # The token comes from `claude setup-token` on a machine already signed in to
  # the subscription -- it prints an sk-ant-oat01- token to paste above. It is
  # the whole of the credential: the unit needs no browser login of its own and
  # no OAuth state, which is why this and not `claude auth login` as the
  # service user. It does eventually expire, and when it does the unit fails
  # loudly rather than silently skipping a day; re-run setup-token then.
  #
  # This spends the same quota as interactive use, so the digest competes with
  # your own sessions for it. Hence sonnet rather than opus above: merging and
  # summarising is well within it, and the opus quota stays yours. A window
  # where even sonnet is unavailable costs the editing, not the mail.
  #
  # The first run would otherwise digest every feed's entire backlog. Deliver
  # that backlog once as an unedited brief, which doubles as the check that the
  # IMAP side works and spends no model quota:
  #
  #   sudo -u rss-digest rss-digest --no-model
  #
  # Or, to throw the backlog away instead of reading it:
  #
  #   sudo -u rss-digest rss-digest --seed-state
  #
  # And the inverse, to undo a delivery so those entries come back on the next
  # run -- every feed, or only the ones named:
  #
  #   sudo -u rss-digest rss-digest --forget
  #   sudo -u rss-digest rss-digest --forget hackernews ft-world
}
