#!/usr/bin/env python3
"""The parts of the feed pipeline that both delivery paths need.

digest.py mails text feeds and podcast-dl.py pulls audio onto disk; what they
share is fetching a feed, deciding what is new, and recording what went out.

The seen-state is `{feed name: {uid: ISO date}}`, written only once something
has actually been delivered -- recording an entry while merely filtering would
lose it for good the first time a later stage failed.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

import feedparser


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def oneline(value: str) -> str:
    """Feed titles arrive with line breaks in them often enough to matter."""
    return " ".join(str(value).split())


def entry_uid(entry) -> str:
    """Stable identity: the feed's guid, else the link, else a hash of the title."""
    for key in ("id", "link"):
        value = entry.get(key)
        if value:
            return str(value)
    seed = (entry.get("title", "") + entry.get("published", "")).encode()
    return "sha1:" + hashlib.sha1(seed).hexdigest()


# --------------------------------------------------------------------------
# fetching


def parse_feed(feed: dict):
    """Fetch one feed, or None when malformed XML left no entries at all."""
    parsed = feedparser.parse(feed["url"])
    if parsed.bozo and not parsed.entries:
        log(f"{feed['name']}: fetch failed: {parsed.get('bozo_exception')}")
        return None
    return parsed


def new_entries(feed: dict, parsed, seen: dict[str, dict]) -> list[tuple]:
    """The undelivered entries of one feed, as (entry, uid).

    A feed's `include` regex is re.search'd against the title, and what does not
    match is treated as though the feed had never carried it -- not returned and
    never recorded, so the state stays the size of what is delivered.
    """
    name = feed["name"]
    known = seen.get(name, {})
    matcher = re.compile(feed["include"]) if feed.get("include") else None
    fresh: list[tuple] = []
    filtered = 0
    for entry in parsed.entries:
        if matcher and not matcher.search(oneline(entry.get("title", ""))):
            filtered += 1
            continue
        uid = entry_uid(entry)
        if uid in known:
            continue
        fresh.append((entry, uid))
    detail = f" ({filtered} filtered out)" if filtered else ""
    log(f"{name}: {len(fresh)} new of {len(parsed.entries)}{detail}")
    return fresh


# --------------------------------------------------------------------------
# the seen-state


def load_state(path: Path) -> dict[str, dict]:
    return json.loads(path.read_text()) if path.exists() else {}


def save_state(path: Path, seen: dict[str, dict]) -> None:
    """Write through a temporary file, so an interrupted write cannot truncate."""
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(seen, ensure_ascii=False, indent=1))
    tmp.replace(path)


def mark_seen(seen: dict[str, dict], feed_name: str, uid: str) -> None:
    seen.setdefault(feed_name, {})[uid] = dt.date.today().isoformat()


def prune_state(seen: dict[str, dict], keep_days: int = 60) -> dict[str, dict]:
    """Forget records older than keep_days, safe only for short-window feeds.

    Dropping a record makes that entry look new again, so a feed carrying years
    of back catalogue must not be pruned -- podcast-dl.py therefore does not.
    """
    cutoff = (dt.date.today() - dt.timedelta(days=keep_days)).isoformat()
    return {
        feed: {uid: day for uid, day in uids.items() if day >= cutoff}
        for feed, uids in seen.items()
    }


def forget_feeds(seen: dict[str, dict], names: list[str]) -> None:
    """Drop the delivery record for these feeds, in place."""
    for name in names:
        if name in seen:
            log(f"{name}: forgetting {len(seen.pop(name))} entries")
        else:
            log(f"{name}: no delivery record to forget")
