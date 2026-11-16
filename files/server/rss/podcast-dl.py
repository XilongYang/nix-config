#!/usr/bin/env python3
"""Podcast feeds -> audio files on disk.

One job: keep a directory holding the newest episodes of a few shows, named so
that a phone browsing a directory listing can tell what it is looking at and
tagged so that whatever imports them shows the right thing.

    <dest>/<show>/YYYY-MM-DD <episode title>.mp3

Each episode is streamed to a hidden .part file beside its target, tagged, and
only then renamed into place. So what the listing shows is always a complete,
tagged file, and the seen-state is committed per episode right after that
rename: a run that dies halfway keeps what it finished and retries the rest
tomorrow. Nothing here sends mail, runs a model, or needs a credential.

Four things are deliberately not done:

  * No transcoding. The files are the publisher's own, byte for byte.
  * No size limit. This is a disk, not a mail server.
  * No pruning of the seen-state. These feeds carry years of back catalogue
    -- 958 entries in one of them -- so dropping a delivery record would make
    an old episode look new again. The state grows by a few entries a day; at
    some 80 bytes each that is noise for a decade.
  * No retry loop. A failed episode is simply not recorded, so the next run
    picks it up again.
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

# Big enough that a 75 MB episode is not a hundred thousand write calls, small
# enough that a stalled connection trips the socket timeout rather than hanging
# inside one read.
CHUNK = 256 * 1024

# Some CDNs answer python-urllib's default User-Agent with a 403. Podcast hosts
# are used to clients naming themselves, so name this one.
USER_AGENT = "podcast-dl/1 (personal podcast fetcher)"

# The extension a player needs in order to open the file at all. A feed's
# declared type is not always a registered one -- NHK says "audio/mp3" -- so
# the map is generous and the fallback is the URL's own suffix.
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

# Characters that make a name awkward over SMB, inside a URL, or in a mobile
# file picker. Japanese stays; this punctuation does not.
AWKWARD = re.compile(r'[/\\:*?"<>|\x00-\x1f]')

# Room for a full episode title while staying well inside the 255-byte limit
# once the date prefix and the extension are in.
MAX_NAME_BYTES = 150


# --------------------------------------------------------------------------
# naming


def tidy(value: str) -> str:
    """One line, NFC, no characters that upset a file system or a URL."""
    return " ".join(AWKWARD.sub(" ", unicodedata.normalize("NFC", oneline(value))).split())


def episode_date(entry) -> dt.date:
    """The broadcast date, which is what belongs in front of the file name.

    feedparser normalises every date it parses to UTC, so the struct_time's own
    day is the wrong one for anything broadcast early in the morning in a
    forward timezone: NHK's 07:20 JST bulletin is 22:20 the previous day in
    UTC, and naming it by that would date every episode a day early. Hence the
    round trip through an epoch stamp, which converts to this machine's zone.

    Falls back to today: a feed without a parseable date is still worth
    fetching, and the prefix only has to sort and be recognisable.
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
    """The first audio enclosure of an entry, as (url, declared type).

    Returns ("", "") when there is none, which is not an error: a feed derived
    from a video site carries a text/html player as its enclosure and simply
    has no file to fetch.
    """
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

    A truncated response is the failure worth catching by hand: it arrives as a
    successful read of too few bytes, and renaming that would publish a cut-off
    episode and record it as delivered.
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
    """Write the tags a player will actually show.

    Worth doing because the hosts these feeds use often ship files whose own
    tags are empty or carry the network's advertising copy, and whatever imports
    the file reads tags rather than names. A failure here is logged and ignored:
    a correctly downloaded episode with poor tags is still the episode.
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
        # The state says undelivered but the file is there: a previous run was
        # killed between the rename and the state write. Nothing to fetch, and
        # the caller will record it this time.
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

    Age is time since download, not since broadcast: measured from the episode
    date, a feed's back catalogue would be deleted the moment it arrived.
    Deleting a file does not bring it back on the next run -- the seen-state
    still has it -- so deleting one by hand after importing it is safe too.
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
    # Low on purpose. These feeds carry hundreds of entries each, so without a
    # cut the first run would pull entire back catalogues; with it, a first run
    # needs no --seed-state and simply fetches the newest few of every show. A
    # feed may raise its own limit with "maxPerRun".
    parser.add_argument("--max-per-feed", type=int, default=3,
                        help="most episodes to fetch per feed per run")
    parser.add_argument("--keep-days", type=int, default=30,
                        help="delete episodes this many days after downloading them")
    parser.add_argument("--timeout", type=int, default=300,
                        help="seconds of silence on the socket before giving up")
    # The first thing to run after adding a show: it prints the episodes the
    # `include` regex selects and the names they would get, and touches nothing.
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
        # Newest first, then cut: what matters is the latest episode, and a feed
        # listing its whole history must never be fetched in full.
        fresh.sort(key=lambda pair: pair[0].get("published_parsed") or (), reverse=True)
        for entry, uid in fresh[:feed.get("maxPerRun", args.max_per_feed)]:
            url, declared = audio_enclosure(entry)
            if args.dry_run:
                describe(entry, url, declared)
                continue
            if args.seed_state:
                mark_seen(seen, feed["name"], uid)
                continue
            if not url:
                # Nothing to fetch, ever. Record it so that it stops occupying
                # one of this feed's slots on every future run.
                log(f"    no audio enclosure: {oneline(entry.get('title', ''))}")
                mark_seen(seen, feed["name"], uid)
                save_state(state_file, seen)
                continue
            attempted += 1
            try:
                fetch_episode(feed, entry, url, declared, dest, args.timeout)
            except Exception as err:
                # One show's bad day must not cost the others theirs. The entry
                # is not recorded, so the next run tries it again.
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
    # Only a total failure is worth failing the unit over: that means the
    # network or every host, not one show. Anything partial has already been
    # committed and the rest retries tomorrow.
    if attempted and failed == attempted:
        sys.exit(f"all {attempted} downloads failed")


if __name__ == "__main__":
    main()
