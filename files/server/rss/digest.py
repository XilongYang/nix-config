#!/usr/bin/env python3
"""RSS -> Claude -> IMAP APPEND.

Each stage writes one file into the day's run directory and is skipped when that
file exists, so a failed run can be re-run without paying for the model twice:

    items.json   entries fetched that the state file has not seen
    brief.json   those entries as a digest, grouped and ordered by rule alone
    digest.json  the same shape after the model has edited it
    mail.eml     the rendered message
    done         written only after the IMAP server acknowledges the APPEND

The model is one optional stage, not the pipeline: brief.json is already a
complete morning brief, and when the model cannot edit it the brief goes out as
it stands with one line at the top saying why.

That failure is deliberately not checkpointed, since nothing was spent on it.

The seen-state is committed only once "done" exists -- nothing is marked seen
merely because it was fetched, which is what makes a re-run safe.
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

import html2text
import jinja2

# Shared with podcast-dl.py, which delivers audio instead of mail.
from feedlib import (
    forget_feeds,
    load_state,
    log,
    mark_seen,
    new_entries,
    oneline,
    parse_feed,
    prune_state,
    save_state,
)

# Enough per entry for the model to judge an article, not enough to run away.
MAX_ENTRY_CHARS = 4000


def load_env_file(path: Path) -> None:
    """Read KEY="value" lines into the environment, without overriding it.

    systemd supplies these through EnvironmentFile, so this is only for the
    modes run by hand.
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
    # Two feeds of one paper carry the same article often enough to matter; the
    # copy is still recorded as seen, but only the first is shown or sent.
    first_seen_in: dict[str, str] = {}
    for feed in feeds:
        name = feed["name"]
        parsed = parse_feed(feed)
        if parsed is None:
            continue
        for entry, uid in new_entries(feed, parsed, seen):
            duplicate = uid in first_seen_in
            if duplicate:
                log(f"{name}: {uid} already came from {first_seen_in[uid]}")
            else:
                first_seen_in[uid] = name
            items.append(
                {
                    "feed": name,
                    "group": feed.get("group", "default"),
                    # A channel title is often the section, not the paper, so
                    # the feed list may override it.
                    "source": oneline(feed.get("source") or parsed.feed.get("title", name)),
                    "uid": uid,
                    "title": oneline(entry.get("title", "(untitled)")),
                    "link": entry.get("link", ""),
                    "published": entry.get("published", entry.get("updated", "")),
                    # Where Hacker News keeps the discussion, its body empty.
                    "comments": entry.get("comments", ""),
                    "text": entry_text(entry),
                    "duplicate": duplicate,
                }
            )
    return items


# --------------------------------------------------------------------------
# stage 2a: the brief, by rule alone

# A group not named here sorts after these, alphabetically.
GROUP_ORDER = ["blogs", "news"]
GROUP_HEADINGS = {"blogs": "Blogs", "news": "News"}

# Enough of each entry to decide whether to open it, in a brief nobody edited.
BRIEF_SUMMARY_CHARS = 400


def presentable(items: list[dict]) -> list[dict]:
    """The items worth showing: everything but the cross-feed duplicates."""
    return [item for item in items if not item.get("duplicate")]


def build_brief(items: list[dict]) -> dict:
    """Render the items as a digest without a model, in the model's own shape."""
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
            # The links are listed below the entry anyway, so a summary that is
            # nothing but links is noise.
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
    """Hand the items to the model, returning (digest, "") or (None, reason).

    Every failure is a reason and never an exit, shown to the reader as it is.
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
        # A pure transformation of stdin, which can then never block on a
        # permission prompt no one is there to answer.
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

    # The two numbers that explain a slow run: this stage generates serially,
    # so its time tracks `out`, of which thinking is part.
    usage = envelope.get("usage", {})
    log(f"model run: {envelope.get('duration_ms', 0) / 1000:.0f}s, "
        f"{envelope.get('num_turns')} turns, "
        f"out {usage.get('output_tokens', 0)} tokens "
        f"({usage.get('output_tokens_details', {}).get('thinking_tokens', 0)} thinking), "
        f"${envelope.get('total_cost_usd', 0):.4f} list-price")
    if envelope.get("is_error"):
        # The first line is the useful part; the rest is for the journal.
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

    The only contract with them is the shape of `digest`, which is the same
    whether the model edited it or not.
    """
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(template_dir),
        # Feed text is not to be trusted in HTML, and escaping the text part
        # would grow &amp; everywhere.
        autoescape=lambda name: bool(name and name.endswith(".html.j2")),
        trim_blocks=True,
        lstrip_blocks=True,
        undefined=jinja2.StrictUndefined,
    )
    # StrictUndefined means every key a template may reach for has to exist,
    # "notice" being the one the model never produces.
    digest = {"title": "", "notice": "", "lede": "", "sections": [], "dropped": [], **digest}

    text = env.get_template("mail.txt.j2").render(digest=digest).strip() + "\n"
    body = env.get_template("mail.html.j2").render(digest=digest)

    msg = EmailMessage()
    msg["Subject"] = digest.get("title") or f"RSS Digest {dt.date.today():%Y-%m-%d}"
    msg["From"] = env_var("RSS_MAIL_FROM")
    msg["To"] = env_var("RSS_MAIL_TO")
    msg["Date"] = email.utils.formatdate(localtime=True)
    # Derived from the content, so a re-run after a half-failed APPEND
    # recognises its own message instead of posting a duplicate.
    msg["Message-ID"] = msg_id
    msg.set_content(text)
    msg.add_alternative(body, subtype="html")
    return msg


# --------------------------------------------------------------------------
# stage 4: append


def append(msg: EmailMessage, folder: str) -> None:
    host = env_var("RSS_IMAP_HOST")
    # A first deployment fails here more often than anywhere else, and nothing
    # is committed yet, so one line beats a traceback.
    try:
        conn = imaplib.IMAP4_SSL(host)
    except OSError as err:
        sys.exit(f"cannot reach {host}: {err}")
    try:
        conn.login(env_var("RSS_IMAP_USER"), env_var("RSS_IMAP_PASSWORD"))
        # create() on an existing mailbox is an error we do not care about.
        conn.create(folder)
        status, _ = conn.select(folder)
        if status != "OK":
            sys.exit(f"cannot select {folder}")
        msg_id = msg["Message-ID"]
        status, data = conn.uid("SEARCH", "HEADER", "Message-ID", msg_id)
        if status != "OK":
            # Not fatal: the worst case is a duplicate, losing it is worse.
            log(f"cannot search {folder} for {msg_id}, appending anyway")
        # A no-match reply is [None] from iCloud and [b""] elsewhere, neither
        # of them the shape imaplib's docs suggest.
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
    # Measured: 72 entries took 411s, so the ceiling is set for a first run
    # over a whole backlog rather than for a daily one.
    parser.add_argument("--timeout", type=int, default=1800,
                        help="seconds to let the model run before giving up "
                             "and delivering the unedited brief")
    # For testing the brief, or running without a usable token at all.
    parser.add_argument("--no-model", action="store_true",
                        help="deliver the unedited brief, do not call the model")
    # Not a bill under a subscription, purely a guard against a feed that
    # suddenly emits thousands of entries.
    parser.add_argument("--max-budget", type=float, default=2.0)
    parser.add_argument("--folder", default=os.environ.get("RSS_IMAP_FOLDER", "RSS"))
    # Run by hand when a feed is added or the state is lost, so that the next
    # run does not digest the whole backlog.
    parser.add_argument("--seed-state", action="store_true",
                        help="mark everything currently in the feeds as seen "
                             "and exit without producing a digest")
    # The way to undo a delivery, today's run directory going with it -- a
    # leftover "done" would make the next run refuse to do anything.
    parser.add_argument("--forget", nargs="*", metavar="FEED", default=None,
                        help="drop the delivery record for these feeds, or for "
                             "every feed when given no names, and exit")
    args = parser.parse_args()

    state_dir = Path(args.state_dir)
    load_env_file(Path(args.env_file) if args.env_file else state_dir / "env")
    state_file = state_dir / "state.json"
    run_dir = state_dir / "runs" / dt.date.today().isoformat()
    run_dir.mkdir(parents=True, exist_ok=True)

    seen: dict[str, dict] = load_state(state_file)
    feeds = json.loads(Path(args.feeds).read_text())

    if args.forget is not None:
        forget_feeds(seen, args.forget or sorted(seen))
        save_state(state_file, seen)
        if run_dir.exists():
            shutil.rmtree(run_dir)
            log(f"removed today's run directory {run_dir}")
        log("nothing was deleted from the mailbox; the next run re-delivers")
        return

    if args.seed_state:
        items = fetch(feeds, seen)
        for item in items:
            mark_seen(seen, item["feed"], item["uid"])
        save_state(state_file, seen)
        log(f"seeded {len(items)} items as seen, nothing sent")
        return

    # A completed run is not repeated; remove the day's run directory to
    # deliberately produce a second digest.
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

    # Always built: it is both the fallback mail and the model's input.
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
            # Only a successful edit is checkpointed, so a re-run after a
            # failure tries the model again.
            digest_file.write_text(json.dumps(digest, ensure_ascii=False, indent=1))
        else:
            digest = brief
            digest["notice"] = (f"Not edited by the model ({reason}). "
                                f"What follows is the raw brief.")
            log(f"falling back to the unedited brief: {reason}")

    # The uids and not the rendered mail, so a template change cannot alter the
    # identity of a digest already delivered.
    seed = "".join(sorted(item["uid"] for item in items)).encode()
    domain = email.utils.parseaddr(env_var("RSS_MAIL_FROM"))[1].partition("@")[2] or "localhost"
    msg_id = (f"<rss-digest.{dt.date.today():%Y%m%d}."
              f"{hashlib.sha1(seed).hexdigest()[:16]}@{domain}>")

    mail_file = run_dir / "mail.eml"
    msg = render(digest, msg_id, args.template_dir)
    mail_file.write_bytes(msg.as_bytes())

    append(msg, args.folder)
    done.write_text(dt.datetime.now().isoformat())

    # Safe only now, and only because these feeds offer days and not years.
    for item in items:
        mark_seen(seen, item["feed"], item["uid"])
    save_state(state_file, prune_state(seen, keep_days=60))
    log(f"committed {len(items)} items as seen")


if __name__ == "__main__":
    main()
