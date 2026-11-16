#!/usr/bin/env python3
"""Podcast feeds -> audio files on disk, named for a phone's directory listing.

    <dest>/<show>/YYYY-MM-DD <episode title>.mp3

Each episode is streamed to a hidden .part file, tagged, renamed into place, and
only then recorded as seen, so a run that dies halfway keeps what it finished.

Deliberately absent: transcoding, a size limit, pruning of the seen-state (these
feeds carry years of back catalogue), and any retry loop.
"""

from __future__ import annotations

import argparse
import calendar
import datetime as dt
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

import mutagen
from mutagen.id3 import COMM, ID3, ID3NoHeaderError, TALB, TDRC, TIT2, TPE1

from feedlib import (
    forget_feeds,
    load_state,
    log,
    mark_seen,
    new_entries,
    oneline,
    parse_feed,
    save_state,
)

# Big enough that a 75 MB episode is not a hundred thousand write calls.
CHUNK = 256 * 1024

# Some CDNs answer python-urllib's default User-Agent with a 403.
USER_AGENT = "podcast-dl/1 (personal podcast fetcher)"

# Generous, because a declared type is not always a registered one -- NHK says
# "audio/mp3" -- and the fallback is the URL's own suffix.
EXTENSIONS = {
    "audio/mpeg": ".mp3",
    "audio/mp3": ".mp3",
    "audio/mp4": ".m4a",
    "audio/x-m4a": ".m4a",
    "audio/aac": ".m4a",
    "audio/ogg": ".ogg",
    "audio/opus": ".opus",
    "audio/wav": ".wav",
}
AUDIO_SUFFIXES = set(EXTENSIONS.values())

# Awkward over SMB, inside a URL, or in a mobile file picker -- Japanese stays.
AWKWARD = re.compile(r'[/\\:*?"<>|\x00-\x1f]')

# Room for a full title well inside the 255-byte limit, prefix and suffix in.
MAX_NAME_BYTES = 150


# --------------------------------------------------------------------------
# naming


def tidy(value: str) -> str:
    """One line, NFC, no characters that upset a file system or a URL."""
    return " ".join(AWKWARD.sub(" ", unicodedata.normalize("NFC", oneline(value))).split())


def episode_date(entry) -> dt.date:
    """The broadcast date, in this machine's zone and not feedparser's UTC.

    NHK's 07:20 JST bulletin is 22:20 the previous day in UTC, so naming it by
    the struct_time's own day would date every episode early -- hence the round
    trip through an epoch stamp.
    """
    parsed = entry.get("published_parsed") or entry.get("updated_parsed")
    if not parsed:
        return dt.date.today()
    return dt.date.fromtimestamp(calendar.timegm(parsed))


def file_name(entry, ext: str) -> str:
    """`YYYY-MM-DD <title><ext>`, trimmed on a character boundary."""
    stem = f"{episode_date(entry):%Y-%m-%d} {tidy(entry.get('title', 'episode'))}".strip()
    budget = MAX_NAME_BYTES - len(ext.encode())
    while len(stem.encode()) > budget:
        stem = stem[:-1]
    # A trailing space or dot survives ext4 but confuses SMB clients.
    return stem.rstrip(" .") + ext


def audio_enclosure(entry) -> tuple[str, str]:
    """The first audio enclosure as (url, type), or ("", "") -- not an error."""
    for enclosure in entry.get("enclosures", []):
        href = enclosure.get("href")
        if href and str(enclosure.get("type", "")).startswith("audio"):
            return href, str(enclosure.get("type", ""))
    return "", ""


def extension(url: str, declared: str) -> str:
    if declared in EXTENSIONS:
        return EXTENSIONS[declared]
    suffix = Path(urllib.parse.urlsplit(url).path).suffix.lower()
    return suffix if suffix in AUDIO_SUFFIXES else ".mp3"


# --------------------------------------------------------------------------
# fetching one episode


def download(url: str, part: Path, timeout: int) -> int:
    """Stream the episode to `part`, or leave nothing behind.

    A truncated response arrives as a successful read of too few bytes, which
    renamed would publish a cut-off episode and record it as delivered.
    """
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    written = 0
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            declared = int(response.headers.get("Content-Length") or 0)
            with part.open("wb") as out:
                while chunk := response.read(CHUNK):
                    out.write(chunk)
                    written += len(chunk)
        if declared and written != declared:
            raise OSError(f"got {written} of {declared} bytes")
    except BaseException:
        part.unlink(missing_ok=True)
        raise
    return written


def tag(path: Path, *, title: str, show: str, date: dt.date, link: str) -> None:
    """Write the tags a player shows, since these hosts' own are often ad copy.

    A failure is logged and ignored: a downloaded episode with poor tags is
    still the episode.
    """
    try:
        if path.suffix == ".mp3":
            try:
                id3 = ID3(path)
            except ID3NoHeaderError:
                id3 = ID3()
            id3.setall("TIT2", [TIT2(encoding=3, text=title)])
            id3.setall("TPE1", [TPE1(encoding=3, text=show)])
            id3.setall("TALB", [TALB(encoding=3, text=show)])
            id3.setall("TDRC", [TDRC(encoding=3, text=date.isoformat())])
            if link:
                id3.setall("COMM", [COMM(encoding=3, lang="eng", desc="", text=link)])
            id3.save(path)
            return
        audio = mutagen.File(path, easy=True)
        if audio is None:
            return
        audio["title"] = title
        audio["artist"] = show
        audio["album"] = show
        audio["date"] = date.isoformat()
        audio.save()
    except Exception as err:  # mutagen raises a wide variety on odd files
        log(f"    could not tag: {err}")


def fetch_episode(feed: dict, entry, url: str, declared: str,
                  dest: Path, timeout: int) -> Path:
    show_dir = dest / tidy(feed["source"])
    show_dir.mkdir(parents=True, exist_ok=True)
    target = show_dir / file_name(entry, extension(url, declared))
    if target.exists():
        # A previous run was killed between the rename and the state write, so
        # there is nothing to fetch and the caller records it this time.
        log(f"    already on disk: {target.name}")
        return target
    part = target.with_name("." + target.name + ".part")
    written = download(url, part, timeout)
    tag(
        part,
        title=oneline(entry.get("title", "")),
        show=feed["source"],
        date=episode_date(entry),
        link=entry.get("link", ""),
    )
    part.replace(target)
    log(f"    {target.name}  {written / 1e6:.1f} MB")
    return target


def describe(entry, url: str, declared: str) -> None:
    """What --dry-run prints: enough to check an `include` regex and a name."""
    if not url:
        log(f"    (no audio enclosure) {oneline(entry.get('title', ''))}")
        return
    log(f"    {file_name(entry, extension(url, declared))}"
        f"  [{entry.get('itunes_duration', '?')}]")
    log(f"        {url[:110]}")


# --------------------------------------------------------------------------
# retention


def prune(dest: Path, keep_days: int) -> None:
    """Delete episodes older than keep_days, and any show directory left empty.

    Age is time since download, not since broadcast: by episode date a back
    catalogue would be deleted the moment it arrived.
    """
    if not dest.exists():
        return
    cutoff = time.time() - keep_days * 86400
    for path in sorted(dest.rglob("*")):
        if (path.is_file() and path.suffix.lower() in AUDIO_SUFFIXES
                and path.stat().st_mtime < cutoff):
            path.unlink()
            log(f"pruned {path.relative_to(dest)}")
    for directory in sorted(dest.iterdir()):
        if directory.is_dir() and not any(directory.iterdir()):
            directory.rmdir()
            log(f"pruned empty {directory.relative_to(dest)}/")


# --------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--feeds", required=True, help="JSON list of podcast feeds")
    parser.add_argument("--dest", required=True, help="directory to fill with episodes")
    parser.add_argument("--state-dir", required=True)
    # Low on purpose: without a cut the first run would pull whole back
    # catalogues, and a feed may raise its own limit with "maxPerRun".
    parser.add_argument("--max-per-feed", type=int, default=3,
                        help="most episodes to fetch per feed per run")
    parser.add_argument("--keep-days", type=int, default=30,
                        help="how far back in a feed to fetch, and how many "
                             "days after downloading an episode to delete it")
    parser.add_argument("--timeout", type=int, default=300,
                        help="seconds of silence on the socket before giving up")
    # The first thing to run after adding a show.
    parser.add_argument("--dry-run", action="store_true",
                        help="print what would be fetched, download nothing")
    parser.add_argument("--seed-state", action="store_true",
                        help="record what the feeds currently offer as delivered "
                             "and exit without downloading")
    parser.add_argument("--forget", nargs="*", metavar="FEED", default=None,
                        help="drop the delivery record for these feeds, or for "
                             "every feed when given no names, and exit")
    args = parser.parse_args()

    dest = Path(args.dest)
    state_file = Path(args.state_dir) / "state.json"
    seen = load_state(state_file)
    feeds = json.loads(Path(args.feeds).read_text())

    if args.forget is not None:
        forget_feeds(seen, args.forget or sorted(seen))
        save_state(state_file, seen)
        log("no files were deleted; the next run fetches them again")
        return

    attempted = failed = 0
    for feed in feeds:
        parsed = parse_feed(feed)
        if parsed is None:
            continue
        fresh = new_entries(feed, parsed, seen)
        if args.seed_state and not args.dry_run:
            # Everything the feed carries, past the window and the per-run cap
            # both, because a slate half wiped is worse than not wiped at all.
            for entry, uid in fresh:
                mark_seen(seen, feed["name"], uid)
            log(f"    {len(fresh)} marked as delivered")
            continue
        # Newest first, then cut: a feed's whole history must never be fetched.
        fresh.sort(key=lambda pair: pair[0].get("published_parsed") or (), reverse=True)
        # Never fetched, and never recorded either: prune() deletes on this same
        # keep_days, so a back catalogue is bandwidth for nothing.
        cutoff = dt.date.today() - dt.timedelta(days=args.keep_days)
        recent = [pair for pair in fresh if episode_date(pair[0]) >= cutoff]
        if len(recent) < len(fresh):
            log(f"    {len(fresh) - len(recent)} older than "
                f"{args.keep_days} days, left alone")
        for entry, uid in recent[:feed.get("maxPerRun", args.max_per_feed)]:
            url, declared = audio_enclosure(entry)
            if args.dry_run:
                describe(entry, url, declared)
                continue
            if not url:
                # Recorded, or it occupies one of this feed's slots every run.
                log(f"    no audio enclosure: {oneline(entry.get('title', ''))}")
                mark_seen(seen, feed["name"], uid)
                save_state(state_file, seen)
                continue
            attempted += 1
            try:
                fetch_episode(feed, entry, url, declared, dest, args.timeout)
            except Exception as err:
                # Not recorded, so the next run tries this one again.
                failed += 1
                log(f"    failed: {oneline(entry.get('title', ''))}: {err}")
                continue
            mark_seen(seen, feed["name"], uid)
            save_state(state_file, seen)

    if args.dry_run:
        return
    if args.seed_state:
        save_state(state_file, seen)
        log("seeded the state, nothing downloaded")
        return

    prune(dest, args.keep_days)
    log(f"{attempted - failed} of {attempted} downloads succeeded")
    # Only a total failure means the network rather than one show's bad day.
    if attempted and failed == attempted:
        sys.exit(f"all {attempted} downloads failed")


if __name__ == "__main__":
    main()
