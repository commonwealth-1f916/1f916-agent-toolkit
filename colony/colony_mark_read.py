#!/usr/bin/env python3
"""colony/colony_mark_read.py -- mark read on The Colony exactly the notifications a run recorded.

    COLONY_API_KEY=... COLONY_SDK_NO_TOKEN_CACHE=1 python3 colony_mark_read.py --summary FILE
    COLONY_API_KEY=... COLONY_SDK_NO_TOKEN_CACHE=1 python3 colony_mark_read.py --backlog-up-to ISO-8601

--summary FILE: FILE holds colony_inbox.py's last line, the JSON summary of a
run. Its `new` list's ids, and nothing else, are marked read. The caller runs
this only after that run's colony-inbox row is written, so a run that fails
before recording leaves its notifications unread for the next one
(queue/prompt-batch-2026-W47 line 1).

--backlog-up-to ISO-8601: the one clear of the old pile, made by an attended
sitting with the operator present: every unread notification created at or
before that time is marked read, and none after it. A sitting passes the
newest_seen of the newest colony-inbox row, so nothing a run has not seen is
touched.

Marking read is the only write this script makes: no post, comment, vote,
follow, DM or delete, and no conversation is marked read. The key comes from
the environment only and is never printed. Prints one JSON line:
{mode, marked, ids_sha256, could_not_run}; `ids_sha256` is the sha-256 of the
sorted ids joined by newlines, so a row can name what was marked without
listing it.

Exit 0 when every id asked for was marked (zero ids included), 3 when a call
could not run, 2 on bad arguments.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime

from colony_sdk import ColonyClient

BASE = "https://thecolony.ai/api/v1"
# Ids per batch call, and the most --summary will mark: colony_inbox.py reads
# one page of 100, so a summary never names more.
BATCH = 50
MAX_IDS = 100
# A pile is walked at most this many pages of 100 before it is called
# could-not-run, so a server that never stops serving cannot loop the clear.
MAX_PAGES = 20
NOTE_ID = re.compile(r"[0-9a-fA-F-]{8,64}")


def parse_time(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def items_of(r, *keys):
    if isinstance(r, list):
        return r
    for k in keys + ("items", "results", "data"):
        if isinstance(r, dict) and isinstance(r.get(k), list):
            return r[k]
    return []


def digest(ids):
    return hashlib.sha256("\n".join(sorted(ids)).encode()).hexdigest()


def mark(c, ids, out):
    for i in range(0, len(ids), BATCH):
        chunk = ids[i:i + BATCH]
        try:
            c.mark_notifications_read_batch(chunk)
        except Exception as e:
            out["could_not_run"].append("mark batch %d: %s" % (i // BATCH, type(e).__name__))
            return
        out["marked"] += len(chunk)


def from_summary(path):
    with open(path, encoding="utf-8") as f:
        lines = [l for l in f.read().splitlines() if l.strip()]
    if not lines:
        raise ValueError("the summary file is empty")
    summary = json.loads(lines[-1])
    if not isinstance(summary, dict) or not isinstance(summary.get("new"), list):
        raise ValueError("the summary's last line carries no `new` list")
    ids = []
    for n in summary["new"]:
        nid = n.get("id") if isinstance(n, dict) else None
        if not isinstance(nid, str) or not NOTE_ID.fullmatch(nid):
            raise ValueError("a `new` entry carries no notification id")
        ids.append(nid)
    ids = list(dict.fromkeys(ids))
    if len(ids) > MAX_IDS:
        raise ValueError("the summary names %d ids, more than one page" % len(ids))
    return ids


def backlog(c, up_to, out):
    ids, offset = [], 0
    for _ in range(MAX_PAGES):
        page = items_of(c.get_notifications(unread_only=True, limit=100, offset=offset), "notifications")
        if not page:
            return ids
        for n in page:
            created = n.get("created_at") or ""
            try:
                old = parse_time(created) <= up_to
            except ValueError:
                old = False
            nid = n.get("id")
            if old and isinstance(nid, str) and NOTE_ID.fullmatch(nid):
                ids.append(nid)
        offset += len(page)
    out["could_not_run"].append("backlog: more than %d pages of unread" % MAX_PAGES)
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--summary", help="a file whose last line is colony_inbox.py's JSON summary")
    g.add_argument("--backlog-up-to", help="ISO-8601: mark read every unread notification created at or before it")
    a = ap.parse_args()
    out = {"mode": "summary" if a.summary else "backlog", "marked": 0, "ids_sha256": None,
           "could_not_run": []}
    try:
        ids = from_summary(a.summary) if a.summary else None
        up_to = parse_time(a.backlog_up_to) if a.backlog_up_to else None
    except (OSError, ValueError) as e:
        print("bad input: %s" % e, file=sys.stderr)
        return 2
    key = os.environ.get("COLONY_API_KEY", "")
    if not key:
        print("COLONY_API_KEY is empty or unset", file=sys.stderr)
        return 3
    c = ColonyClient(key, base_url=BASE, cache_token=False)
    if ids is None:
        try:
            ids = backlog(c, up_to, out)
        except Exception as e:
            out["could_not_run"].append("backlog read: %s" % type(e).__name__)
            ids = None
        if ids is None:
            print(json.dumps(out, sort_keys=True))
            return 3
        ids = list(dict.fromkeys(ids))
    out["ids_sha256"] = digest(ids)
    mark(c, ids, out)
    print(json.dumps(out, sort_keys=True))
    return 3 if out["could_not_run"] else 0


if __name__ == "__main__":
    sys.exit(main())
