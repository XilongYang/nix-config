#!/usr/bin/env python3
"""The parts of the feed pipeline that both delivery paths need.

Two services read the same feed-list format and keep the same kind of
seen-state: digest.py turns text feeds into one daily mail, podcast-dl.py pulls
audio enclosures onto disk. What they share is not the interesting half --
fetching a feed, deciding which entries are new, recording what has been
delivered -- but it is the half that must not drift apart in two copies.
Everything about *what to do* with an entry stays in the two scripts.

The seen-state is `{feed name: {uid: ISO date}}`. It is written only once
something has actually been delivered, never merely because an entry was
fetched: a fetcher that records an entry as seen while filtering, before
anything has gone out, loses that entry for good the first time a later stage
fails.
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


# --------------------------------------------------------------------------
# fetching


def parse_feed(feed: dict):
    """Fetch and parse one feed, or return None when nothing came back.

    bozo means the parser hit malformed XML. It still returns whatever it could
    salvage, so on its own that is a warning and not a reason to abort a run
    over the other feeds.
    """
    parsed = feedparser.parse(feed["url"])
    if parsed.bozo and not parsed.entries:
        log(f"{feed['name']}: fetch failed: {parsed.get('bozo_exception')}")
        return None
    return parsed


def new_entries(feed: dict, parsed, seen: dict[str, dict]) -> list[tuple]:
    """The entries of one feed that have not been delivered yet, as (entry, uid).

    A feed may carry an `include` regex, matched against the entry title with
    re.search -- so anchor it yourself if you mean to. Anything that does not
    match is treated as though the feed had never carried it: not returned and,
    the point, never recorded as seen, so the state file stays the size of what
    is actually delivered. The case this exists for is one feed that carries
    every programme a station broadcasts when only one of them is wanted.
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
    """Write through a temporary file, so an interrupted write cannot truncate.

    Losing this file means re-delivering everything the feeds still carry, so
    it is worth the rename.
    """
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(seen, ensure_ascii=False, indent=1))
    tmp.replace(path)


def mark_seen(seen: dict[str, dict], feed_name: str, uid: str) -> None:
    seen.setdefault(feed_name, {})[uid] = dt.date.today().isoformat()


def prune_state(seen: dict[str, dict], keep_days: int = 60) -> dict[str, dict]:
    """Forget delivery records older than keep_days.

    Only safe for a caller whose feeds offer a short window: dropping a record
    makes that entry look new again, so a feed that still carries years of back
    catalogue must not be pruned at all. podcast-dl.py therefore does not.
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
