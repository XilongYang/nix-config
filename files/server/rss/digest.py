#!/usr/bin/env python3
"""RSS -> Claude -> IMAP APPEND.

Four stages. Each writes one file into the day's run directory and is skipped
when that file already exists, so a failed run can be re-run the same day
without re-fetching and, more to the point, without paying for the model a
second time:

    items.json   entries fetched that the state file has not seen
    brief.json   those entries as a digest, grouped and ordered by rule alone
    digest.json  the same shape after the model has edited it
    mail.eml     the rendered message
    done         written only after the IMAP server acknowledges the APPEND

The model is one optional stage in the middle, not the pipeline. brief.json is
produced without it and is already a complete, renderable morning brief; the
model's job is to merge, judge and summarise that brief into digest.json. When
it cannot -- rate-limited, token expired, timed out, bad output -- the brief is
delivered as it stands with one line at the top saying so, and the run is
counted as delivered. A missing model costs the reader editing, never the mail.
Note that this stage is therefore deliberately NOT checkpointed when it fails:
nothing was spent, so a re-run gets another attempt at it.

The seen-state is committed only once "done" exists. Nothing is ever marked
seen merely because it was fetched, which is what makes a multi-stage pipeline
safe to retry: a fetcher that records an entry as seen while filtering, before
anything has been delivered, loses that entry for good the first time a later
stage fails.
"""

from __future__ import annotations

import argparse
import datetime as dt
import email.utils
import hashlib
import imaplib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from email.message import EmailMessage
from pathlib import Path

import feedparser
import html2text
import jinja2

# Per-entry text handed to the model. Long enough for the model to judge an
# article, short enough that one runaway feed cannot blow up the bill.
MAX_ENTRY_CHARS = 4000


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def load_env_file(path: Path) -> None:
    """Read KEY="value" lines into the environment, without overriding it.

    systemd already supplies these through EnvironmentFile, so this changes
    nothing under the timer. It exists so that running the command by hand --
    to seed the state, to re-run a failed delivery, to look at the brief with
    --no-model -- needs no shell incantation to find the credentials.
    """
    if not path.exists():
        return
    try:
        content = path.read_text()
    except PermissionError:
        sys.exit(f"cannot read {path}: run as the rss-digest user "
                 f"(sudo -u rss-digest rss-digest ...)")
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        os.environ.setdefault(key, value)


def env_var(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        sys.exit(f"{name} is not set")
    return value


# --------------------------------------------------------------------------
# stage 1: fetch


def entry_uid(entry) -> str:
    """Stable identity for an entry.

    Prefer the feed's own guid, fall back to the link, and only then to a hash
    of the title plus date -- a feed that supplies neither is rare but must not
    produce a new uid on every run.
    """
    for key in ("id", "link"):
        value = entry.get(key)
        if value:
            return str(value)
    seed = (entry.get("title", "") + entry.get("published", "")).encode()
    return "sha1:" + hashlib.sha1(seed).hexdigest()


def oneline(value: str) -> str:
    """Feed titles arrive with line breaks in them often enough to matter."""
    return " ".join(str(value).split())


def entry_text(entry) -> str:
    html_body = ""
    if entry.get("content"):
        html_body = entry["content"][0].get("value", "")
    if not html_body:
        html_body = entry.get("summary", "")
    converter = html2text.HTML2Text()
    converter.ignore_images = True
    converter.ignore_emphasis = True
    converter.body_width = 0
    text = converter.handle(html_body).strip()
    if len(text) > MAX_ENTRY_CHARS:
        text = text[:MAX_ENTRY_CHARS] + "\n[truncated]"
    return text


def fetch(feeds: list[dict], seen: dict[str, dict]) -> list[dict]:
    items: list[dict] = []
    # Two feeds of one publication carry the same article often enough to
    # matter: both FT feeds ran the same midterms piece on the day this was
    # written. The copy is still recorded as seen under its own feed -- else it
    # would come back every run -- but only the first is shown or sent to the
    # model.
    first_seen_in: dict[str, str] = {}
    for feed in feeds:
        name = feed["name"]
        parsed = feedparser.parse(feed["url"])
        # bozo means the parser hit malformed XML. It still returns whatever it
        # could salvage, so this is a warning and not a reason to abort a run
        # over the other feeds.
        if parsed.bozo and not parsed.entries:
            log(f"{name}: fetch failed: {parsed.get('bozo_exception')}")
            continue
        known = seen.get(name, {})
        fresh = 0
        for entry in parsed.entries:
            uid = entry_uid(entry)
            if uid in known:
                continue
            duplicate = uid in first_seen_in
            if duplicate:
                log(f"{name}: {uid} already came from {first_seen_in[uid]}")
            else:
                first_seen_in[uid] = name
            items.append(
                {
                    "feed": name,
                    "group": feed.get("group", "default"),
                    # A feed's own channel title is often useless as a source
                    # name -- FT's two feeds call themselves "Technology" and
                    # "World", naming the section rather than the paper -- so
                    # the feed list may override it.
                    "source": oneline(feed.get("source") or parsed.feed.get("title", name)),
                    "uid": uid,
                    "title": oneline(entry.get("title", "(untitled)")),
                    "link": entry.get("link", ""),
                    "published": entry.get("published", entry.get("updated", "")),
                    # Hacker News items are a link plus a discussion; the feed
                    # keeps the discussion here and almost nothing in the body.
                    "comments": entry.get("comments", ""),
                    "text": entry_text(entry),
                    "duplicate": duplicate,
                }
            )
            fresh += 1
        log(f"{name}: {fresh} new of {len(parsed.entries)}")
    return items


# --------------------------------------------------------------------------
# stage 2a: the brief, by rule alone

# Groups the reader cares about most, first. A group not named here sorts after
# these, alphabetically, so adding one to the feed list needs no change.
GROUP_ORDER = ["blogs", "news"]
GROUP_HEADINGS = {"blogs": "Blogs", "news": "News"}

# Enough of each entry to decide whether to open it, in a brief nobody edited.
BRIEF_SUMMARY_CHARS = 400


def presentable(items: list[dict]) -> list[dict]:
    """The items worth showing: everything but the cross-feed duplicates."""
    return [item for item in items if not item.get("duplicate")]


def build_brief(items: list[dict]) -> dict:
    """Render the items as a digest without a model.

    Same shape the model is asked to produce, so one renderer serves both: this
    is what gets delivered when the model is unavailable, and what the model is
    handed when it is.
    """
    def group_key(group: str) -> tuple[int, str]:
        return (GROUP_ORDER.index(group) if group in GROUP_ORDER else len(GROUP_ORDER), group)

    items = presentable(items)
    sections = []
    groups = sorted({item["group"] for item in items}, key=group_key)
    for group in groups:
        members = [item for item in items if item["group"] == group]
        entries = []
        for item in members:
            summary = " ".join(item["text"].split())
            # Some feeds -- Hacker News above all -- carry no body at all, just
            # a pointer to the discussion. Those links are listed below the
            # entry anyway, so a summary that is nothing but links is noise.
            if not re.sub(r"\[[^\]]*\]\([^)]*\)", "", summary).strip():
                summary = ""
            elif len(summary) > BRIEF_SUMMARY_CHARS:
                summary = summary[:BRIEF_SUMMARY_CHARS] + "…"
            links = []
            if item["link"]:
                links.append({"label": item["source"], "url": item["link"]})
            if item.get("comments"):
                links.append({"label": "HN discussion", "url": item["comments"]})
            entries.append(
                {"title": item["title"], "summary": summary, "links": links}
            )
        sections.append(
            {
                "heading": f"{GROUP_HEADINGS.get(group, group)} ({len(entries)})",
                "items": entries,
            }
        )
    return {
        "title": (f"{dt.date.today():%m-%d} Brief · {len(items)} "
                  f"item{'' if len(items) == 1 else 's'}"),
        "lede": "",
        "sections": sections,
        "dropped": [],
    }


# --------------------------------------------------------------------------
# stage 2b: orchestrate


def orchestrate(args, items: list[dict]) -> tuple[dict | None, str]:
    """Hand the items to the model. Returns (digest, "") or (None, reason).

    Every failure is a reason, never an exit: the caller falls back to the
    unedited brief. The reason is short because it is shown to the reader.
    """
    payload = {
        "date": dt.date.today().isoformat(),
        "items": [
            {k: v for k, v in item.items() if k not in ("uid", "duplicate")}
            for item in presentable(items)
        ],
    }
    cmd = [
        "claude",
        "-p",
        "--output-format", "json",
        "--system-prompt-file", args.prompt,
        "--json-schema", Path(args.schema).read_text(),
        "--model", args.model,
        # No tools: this is a pure transformation of the payload on stdin, and
        # a tool call here could only be a web fetch the schema has no slot
        # for. Both flags together also mean nothing can ever block on a
        # permission prompt that no one is there to answer.
        "--tools", "",
        "--permission-prompts", "none",
        "--no-session-persistence",
        "--max-budget-usd", str(args.max_budget),
    ]
    try:
        proc = subprocess.run(
            cmd,
            input=json.dumps(payload, ensure_ascii=False),
            capture_output=True,
            text=True,
            cwd=args.state_dir,  # keeps any project CLAUDE.md out of the prompt
            timeout=args.timeout,
        )
    except subprocess.TimeoutExpired:
        return None, f"timed out after {args.timeout}s"
    except OSError as err:  # claude not on PATH, not executable, ...
        return None, f"cannot run claude: {err.strerror}"

    if proc.returncode != 0:
        log(proc.stderr.strip()[-2000:])
        return None, f"claude exited {proc.returncode}"
    try:
        envelope = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None, "claude output was not JSON"

    # Wall clock and the thinking share of the output are the two numbers that
    # explain a slow run, so both go in the journal rather than being
    # guessed at later. This stage is output-token-bound: it generates serially,
    # so the time it takes tracks `out`, and thinking is part of `out`.
    usage = envelope.get("usage", {})
    log(f"model run: {envelope.get('duration_ms', 0) / 1000:.0f}s, "
        f"{envelope.get('num_turns')} turns, "
        f"out {usage.get('output_tokens', 0)} tokens "
        f"({usage.get('output_tokens_details', {}).get('thinking_tokens', 0)} thinking), "
        f"${envelope.get('total_cost_usd', 0):.4f} list-price")
    if envelope.get("is_error"):
        # The first line is the useful part: "Not logged in", a rate-limit
        # notice, the budget cap. The rest is for the journal, not the reader.
        detail = str(envelope.get("result", "")).strip().splitlines()
        log(f"claude failed: {' '.join(detail)}")
        return None, detail[0] if detail else "claude reported an error"
    digest = envelope.get("structured_output")
    if not digest:
        return None, "claude returned no structured output"
    return digest, ""


# --------------------------------------------------------------------------
# stage 3: render


def render(digest: dict, msg_id: str, template_dir: str) -> EmailMessage:
    """Turn the digest into a mail using the templates, which own the layout.

    Nothing about the appearance of the mail lives in this file: both parts
    come from template_dir, and the only contract with them is the shape of
    `digest` -- the same shape whether the model edited it or not.
    """
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(template_dir),
        # Feed text is not to be trusted in an HTML part; the text part must
        # not be escaped or it grows &amp; everywhere.
        autoescape=lambda name: bool(name and name.endswith(".html.j2")),
        trim_blocks=True,
        lstrip_blocks=True,
        undefined=jinja2.StrictUndefined,
    )
    # StrictUndefined turns a typo in a template into an error instead of a
    # silently empty mail, which means every key a template may reach for has
    # to exist. "notice" is the one the model never produces.
    digest = {"title": "", "notice": "", "lede": "", "sections": [], "dropped": [], **digest}

    text = env.get_template("mail.txt.j2").render(digest=digest).strip() + "\n"
    body = env.get_template("mail.html.j2").render(digest=digest)

    msg = EmailMessage()
    msg["Subject"] = digest.get("title") or f"RSS Digest {dt.date.today():%Y-%m-%d}"
    msg["From"] = env_var("RSS_MAIL_FROM")
    msg["To"] = env_var("RSS_MAIL_TO")
    msg["Date"] = email.utils.formatdate(localtime=True)
    # Stable and derived from the content, so a re-run after a half-failed
    # APPEND can recognise its own message on the server instead of posting a
    # duplicate. See append().
    msg["Message-ID"] = msg_id
    msg.set_content(text)
    msg.add_alternative(body, subtype="html")
    return msg


# --------------------------------------------------------------------------
# stage 4: append


def append(msg: EmailMessage, folder: str) -> None:
    host = env_var("RSS_IMAP_HOST")
    # A first deployment fails here more often than anywhere else -- wrong
    # host, app password not created, folder nested under INBOX -- so say what
    # happened in one line instead of a traceback. Nothing has been committed
    # at this point, so fixing the cause and re-running is the whole recovery.
    try:
        conn = imaplib.IMAP4_SSL(host)
    except OSError as err:
        sys.exit(f"cannot reach {host}: {err}")
    try:
        conn.login(env_var("RSS_IMAP_USER"), env_var("RSS_IMAP_PASSWORD"))
        # iCloud has the folder already in practice; create() on an existing
        # mailbox is an error we do not care about.
        conn.create(folder)
        status, _ = conn.select(folder)
        if status != "OK":
            sys.exit(f"cannot select {folder}")
        msg_id = msg["Message-ID"]
        status, data = conn.uid("SEARCH", "HEADER", "Message-ID", msg_id)
        if status != "OK":
            # Not fatal: the worst case is a duplicate, and only if a previous
            # run's APPEND did land. Losing the digest would be worse.
            log(f"cannot search {folder} for {msg_id}, appending anyway")
        # A no-match reply comes back as [None] from iCloud and as [b""]
        # elsewhere, so neither the list nor its contents can be trusted to be
        # the shape imaplib's docs suggest.
        elif b" ".join(filter(None, data or [])).split():
            log(f"{msg_id} already on the server, not appending again")
            return
        # flags=None leaves the message unread, which is the entire point.
        status, resp = conn.append(
            folder, None, imaplib.Time2Internaldate(time.time()), msg.as_bytes()
        )
        if status != "OK":
            sys.exit(f"APPEND failed: {resp!r}")
        log(f"appended to {folder}: {resp!r}")
    except (imaplib.IMAP4.error, OSError) as err:
        sys.exit(f"IMAP error against {host}: {err}")
    finally:
        try:
            conn.logout()
        except Exception:
            pass


# --------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feeds", required=True, help="JSON list of feeds")
    parser.add_argument("--schema", required=True, help="JSON schema for the digest")
    parser.add_argument("--prompt", required=True, help="system prompt file")
    parser.add_argument("--template-dir", required=True,
                        help="directory holding mail.html.j2 and mail.txt.j2")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--env-file", default=None,
                        help="credentials file; defaults to env in --state-dir")
    parser.add_argument("--model", default="sonnet")
    # Measured: 72 entries took 411s, 44.7k output tokens at ~109 tokens/s --
    # this stage is output-bound and generates serially, so the time scales
    # with how much there is to write. A first run over a full backlog is
    # several times a normal day's volume, so the ceiling is set for that case,
    # not for the daily one.
    parser.add_argument("--timeout", type=int, default=1800,
                        help="seconds to let the model run before giving up "
                             "and delivering the unedited brief")
    # The model layer is optional by design; this turns it off outright, for
    # testing the brief or for running without a usable token at all.
    parser.add_argument("--no-model", action="store_true",
                        help="deliver the unedited brief, do not call the model")
    # Under a subscription this is not a bill -- claude reports cost at list
    # price for accounting only -- so it serves purely as a runaway guard: a
    # feed that suddenly emits thousands of entries aborts instead of eating
    # the day's quota.
    parser.add_argument("--max-budget", type=float, default=2.0)
    parser.add_argument("--folder", default=os.environ.get("RSS_IMAP_FOLDER", "RSS"))
    # Run once, by hand, when a feed is added or the state is lost: records
    # everything currently in the feeds as seen and sends nothing. Without it
    # the first run digests each feed's entire backlog -- 72 entries across
    # these six feeds, when last measured. An exact guard rather than the usual
    # "only entries newer than N hours" approximation.
    parser.add_argument("--seed-state", action="store_true",
                        help="mark everything currently in the feeds as seen "
                             "and exit without producing a digest")
    # The inverse of --seed-state, and the way to undo a delivery: the entries
    # come back on the next run as though they had never been sent. Today's run
    # directory goes with them, because leaving "done" behind would make that
    # next run refuse to do anything.
    parser.add_argument("--forget", nargs="*", metavar="FEED", default=None,
                        help="drop the delivery record for these feeds, or for "
                             "every feed when given no names, and exit")
    args = parser.parse_args()

    state_dir = Path(args.state_dir)
    load_env_file(Path(args.env_file) if args.env_file else state_dir / "env")
    state_file = state_dir / "state.json"
    run_dir = state_dir / "runs" / dt.date.today().isoformat()
    run_dir.mkdir(parents=True, exist_ok=True)

    seen: dict[str, dict] = json.loads(state_file.read_text()) if state_file.exists() else {}
    feeds = json.loads(Path(args.feeds).read_text())

    if args.forget is not None:
        names = args.forget or sorted(seen)
        for name in names:
            if name in seen:
                log(f"{name}: forgetting {len(seen.pop(name))} entries")
            else:
                log(f"{name}: no delivery record to forget")
        state_file.write_text(json.dumps(seen, ensure_ascii=False, indent=1))
        if run_dir.exists():
            shutil.rmtree(run_dir)
            log(f"removed today's run directory {run_dir}")
        log("nothing was deleted from the mailbox; the next run re-delivers")
        return

    if args.seed_state:
        items = fetch(feeds, seen)
        for item in items:
            seen.setdefault(item["feed"], {})[item["uid"]] = dt.date.today().isoformat()
        state_file.write_text(json.dumps(seen, ensure_ascii=False, indent=1))
        log(f"seeded {len(items)} items as seen, nothing sent")
        return

    # A completed run is not repeated. Re-running after a failure resumes from
    # the last checkpoint instead, because "done" is the one file that only
    # exists once the IMAP server has acknowledged the message. To deliberately
    # produce a second digest the same day, remove the day's run directory.
    done = run_dir / "done"
    if done.exists():
        log(f"already delivered today ({done.read_text()}), nothing to do")
        return

    items_file = run_dir / "items.json"
    if items_file.exists():
        items = json.loads(items_file.read_text())
        log(f"reusing {len(items)} fetched items")
    else:
        items = fetch(feeds, seen)
        items_file.write_text(json.dumps(items, ensure_ascii=False, indent=1))
    if not items:
        log("nothing new")
        return

    # The brief always exists, with or without a model. It is both the
    # fallback mail and the model's input.
    brief = build_brief(items)
    (run_dir / "brief.json").write_text(json.dumps(brief, ensure_ascii=False, indent=1))

    digest_file = run_dir / "digest.json"
    if digest_file.exists():
        digest = json.loads(digest_file.read_text())
        log("reusing the model's output")
    elif args.no_model:
        digest = brief
        log("--no-model: delivering the unedited brief")
    else:
        edited, reason = orchestrate(args, items)
        if edited:
            digest = edited
            # Only a successful edit is checkpointed. A failure is not, so a
            # re-run tries the model again rather than re-delivering a brief
            # that nothing was spent on.
            digest_file.write_text(json.dumps(digest, ensure_ascii=False, indent=1))
        else:
            digest = brief
            digest["notice"] = (f"Not edited by the model ({reason}). "
                                f"What follows is the raw brief.")
            log(f"falling back to the unedited brief: {reason}")

    # Hash the uids rather than the rendered mail, so re-rendering (a template
    # change, say) does not change the identity of a digest already delivered.
    seed = "".join(sorted(item["uid"] for item in items)).encode()
    domain = email.utils.parseaddr(env_var("RSS_MAIL_FROM"))[1].partition("@")[2] or "localhost"
    msg_id = (f"<rss-digest.{dt.date.today():%Y%m%d}."
              f"{hashlib.sha1(seed).hexdigest()[:16]}@{domain}>")

    mail_file = run_dir / "mail.eml"
    msg = render(digest, msg_id, args.template_dir)
    mail_file.write_bytes(msg.as_bytes())

    append(msg, args.folder)
    done.write_text(dt.datetime.now().isoformat())

    # Only now is it safe to forget these entries.
    for item in items:
        seen.setdefault(item["feed"], {})[item["uid"]] = dt.date.today().isoformat()
    cutoff = (dt.date.today() - dt.timedelta(days=60)).isoformat()
    seen = {
        feed: {uid: day for uid, day in uids.items() if day >= cutoff}
        for feed, uids in seen.items()
    }
    tmp = state_file.with_suffix(".tmp")
    tmp.write_text(json.dumps(seen, ensure_ascii=False, indent=1))
    tmp.replace(state_file)
    log(f"committed {len(items)} items as seen")


if __name__ == "__main__":
    main()
