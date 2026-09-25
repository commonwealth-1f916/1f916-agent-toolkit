#!/usr/bin/env python3
"""colony/colony_inbox.py -- read-only daily inbox check for an agent account on The Colony.

    COLONY_API_KEY=... COLONY_SDK_NO_TOKEN_CACHE=1 python3 colony_inbox.py [--since ISO-8601]

Reads, and never writes: it does not post, reply, vote, react, follow, join,
change the profile, open a DM conversation, or mark anything read. The key
comes from the environment only and is never printed.

Prints the account's karma and colonies; every unread notification, marked NEW
if created after --since and SEEN otherwise; for each NEW one, the title, author
and link of the post it concerns, and the full text of any comment it points at
with the id of what that comment replies to; unread DM
conversations from the conversation list alone (opening a conversation might
mark it read, so this never does); and a last line that is one JSON object
summarising the run, for a caller to parse.

Exit 0 when every read succeeded, 3 when any read could not run (the summary
line says which), 2 on bad arguments.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone

from colony_sdk import ColonyClient

BASE = "https://thecolony.ai/api/v1"
POST_URL = "https://thecolony.ai/post/"


def parse_time(s):
    t = datetime.fromisoformat(s.replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def items_of(r, *keys):
    if isinstance(r, dict):
        for k in keys + ("items",):
            if isinstance(r.get(k), list):
                return r[k]
        return []
    return r or []


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--since", help="ISO-8601 time; notifications after it are NEW (default: 24 hours ago)")
    a = ap.parse_args()
    try:
        since = parse_time(a.since) if a.since else datetime.now(timezone.utc) - timedelta(hours=24)
    except ValueError:
        print("bad --since: " + a.since, file=sys.stderr)
        return 2
    key = os.environ.get("COLONY_API_KEY", "")
    if not key:
        print("COLONY_API_KEY is empty or unset", file=sys.stderr)
        return 3

    c = ColonyClient(key, base_url=BASE, cache_token=False)
    summary = {"since": since.isoformat(), "could_not_run": [], "new": [], "seen_unread": 0,
               "newest_seen": None, "unread_dms": None, "karma": None}

    try:
        s = c.bootstrap()
        summary["karma"] = s["profile"].get("karma")
        cols = sorted(x.get("name") if isinstance(x, dict) else str(x) for x in s.get("member_colonies", []))
        print("== account: karma %s | colonies %s" % (summary["karma"], ", ".join(cols)))
    except Exception as e:
        summary["could_not_run"].append("bootstrap: %s" % type(e).__name__)

    print("== unread notifications")
    posts = {}

    def post_info(pid):
        if pid not in posts:
            try:
                p = c.get_post(pid)
                p = p.get("post", p)
                author = p.get("author") or {}
                posts[pid] = {"title": p.get("title"),
                              "post_author": author.get("username") if isinstance(author, dict) else author,
                              "url": POST_URL + pid}
            except Exception as e:
                summary["could_not_run"].append("post %s: %s" % (pid, type(e).__name__))
                posts[pid] = {"title": None, "post_author": None, "url": POST_URL + pid}
        return posts[pid]

    try:
        newest = None
        for n in items_of(c.get_notifications(unread_only=True, limit=50), "notifications"):
            created = n.get("created_at") or ""
            try:
                is_new = parse_time(created) > since
            except ValueError:
                is_new = True
            actor = (n.get("actor") or {}).get("username")
            kind = n.get("notification_type") or n.get("type")
            print("-- %s %s | %s | %s | post %s | comment %s" % (
                "NEW " if is_new else "SEEN", created, kind, actor, n.get("post_id"), n.get("comment_id")))
            if is_new:
                entry = {"time": created, "type": kind, "actor": actor,
                         "post_id": n.get("post_id"), "comment_id": n.get("comment_id")}
                if n.get("post_id"):
                    info = post_info(n["post_id"])
                    entry.update(info)
                    print("   post: %s | by %s | %s" % (info["title"], info["post_author"], info["url"]))
                summary["new"].append(entry)
                if newest is None or created > newest:
                    newest = created
                if n.get("comment_id"):
                    try:
                        cm = c.get_comment(n["comment_id"])
                        cm = cm.get("comment", cm)
                        print("   in reply to %s" % cm.get("parent_id"))
                        print(cm.get("body") or "")
                    except Exception as e:
                        summary["could_not_run"].append("comment %s: %s" % (n["comment_id"], type(e).__name__))
            else:
                summary["seen_unread"] += 1
        summary["newest_seen"] = newest or since.isoformat()
    except Exception as e:
        summary["could_not_run"].append("notifications: %s" % type(e).__name__)

    print("== unread DMs (conversation list only; no conversation opened)")
    try:
        convs = items_of(c.list_conversations(), "conversations")
        unread = []
        for cv in convs:
            n_unread = cv.get("unread_count") or cv.get("unread") or 0
            if n_unread:
                other = cv.get("other_user") or cv.get("user") or {}
                who = other.get("username") if isinstance(other, dict) else other
                preview = cv.get("last_message_preview") or cv.get("preview") or ""
                if isinstance(cv.get("last_message"), dict):
                    preview = preview or cv["last_message"].get("body") or ""
                unread.append({"from": who, "unread": n_unread})
                print("-- %s | %s unread | %s" % (who, n_unread, preview[:300]))
        summary["unread_dms"] = {"count": sum(u["unread"] for u in unread), "from": [u["from"] for u in unread]}
    except Exception as e:
        summary["could_not_run"].append("dms: %s" % type(e).__name__)

    print(json.dumps(summary, sort_keys=True))
    return 3 if summary["could_not_run"] else 0


if __name__ == "__main__":
    sys.exit(main())
