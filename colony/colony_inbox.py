#!/usr/bin/env python3
"""colony/colony_inbox.py -- read-only daily inbox check for an agent account on The Colony.

    COLONY_API_KEY=... COLONY_SDK_NO_TOKEN_CACHE=1 python3 colony_inbox.py [--since ISO-8601]

Reads, and never writes: it does not post, reply, vote, react, follow, join,
change the profile, open a DM conversation, or mark anything read. The key
comes from the environment only and is never printed.

Prints the account's karma and colonies; every unread notification, marked NEW
if created after --since and SEEN otherwise; for each NEW one, the title, author,
tags, link and the opening of the body of the post it concerns (a title alone
often does not say what a post is about), and the full text of any comment it
points at with the id of what that comment replies to; a digest of each member
colony -- of the posts created since --since, the newest and the highest-scored
few, each with its opening lines; unread DM
conversations from the conversation list alone (opening a conversation might
mark it read, so this never does); and a last line that is one JSON object
summarising the run, for a caller to parse.

The summary carries unread_total (the server's own count), page_returned and
page_full: nothing here marks a notification read, so the unread pile grows,
and a full page hides the oldest unread. When the oldest item on a full page is
still NEW, NEW notifications may be missing, and that is a could-not-run.

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
# The colony digest: per member colony, of the posts created since --since,
# the DIGEST_NEWEST newest and the DIGEST_TOP highest-scored. One page of
# DIGEST_PAGE newest posts is read per colony; a colony whose whole page is
# newer than --since says so, because its top pick was drawn from that page
# alone. The API's own "top" sort has no time window, so it would serve the
# same all-time posts every day; ranking the day's posts here is the point.
DIGEST_NEWEST = 3
DIGEST_TOP = 3
DIGEST_PAGE = 50

# The most notifications one request returns (the API's own ceiling). Nothing
# here marks a notification read, so the unread pile only grows; when it is
# larger than one page the oldest unread drop off the end of it, which is
# harmless while they are SEEN and is a lost notification when one is NEW.
PAGE = 100
# Characters of a post's body printed under its title: enough to say what the
# post is about, short enough that fifty notifications stay readable. The full
# post is one click away at its link.
EXCERPT_CHARS = 400


def excerpt(text, limit=EXCERPT_CHARS):
    """The opening of a body on one line: whitespace collapsed, cut at `limit`
    characters with an ellipsis when cut. None when there is no body."""
    if not isinstance(text, str) or not text.strip():
        return None
    flat = " ".join(text.split())
    return flat if len(flat) <= limit else flat[:limit].rstrip() + "…"


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
               "newest_seen": None, "unread_dms": None, "karma": None,
               "unread_total": None, "page_returned": None, "page_full": None}

    cols = []
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
                tags = p.get("tags")
                posts[pid] = {"title": p.get("title"),
                              "post_author": author.get("username") if isinstance(author, dict) else author,
                              "tags": [str(t) for t in tags] if isinstance(tags, list) else [],
                              "excerpt": excerpt(p.get("body")),
                              "url": POST_URL + pid}
            except Exception as e:
                summary["could_not_run"].append("post %s: %s" % (pid, type(e).__name__))
                posts[pid] = {"title": None, "post_author": None, "tags": [], "excerpt": None,
                              "url": POST_URL + pid}
        return posts[pid]

    try:
        try:
            cnt = c.get_notification_count()
            summary["unread_total"] = cnt.get("unread_notifications", cnt.get("unread_count"))
        except Exception as e:
            summary["could_not_run"].append("notification count: %s" % type(e).__name__)
        newest = None
        oldest_is_new = False
        page = items_of(c.get_notifications(unread_only=True, limit=PAGE), "notifications")
        summary["page_returned"] = len(page)
        summary["page_full"] = len(page) >= PAGE
        for n in page:
            created = n.get("created_at") or ""
            try:
                is_new = parse_time(created) > since
            except ValueError:
                is_new = True
            actor = (n.get("actor") or {}).get("username")
            kind = n.get("notification_type") or n.get("type")
            print("-- %s %s | %s | %s | post %s | comment %s" % (
                "NEW " if is_new else "SEEN", created, kind, actor, n.get("post_id"), n.get("comment_id")))
            oldest_is_new = is_new
            if is_new:
                entry = {"time": created, "type": kind, "actor": actor,
                         "post_id": n.get("post_id"), "comment_id": n.get("comment_id")}
                if n.get("post_id"):
                    info = post_info(n["post_id"])
                    entry.update(info)
                    print("   post: %s | by %s | %s" % (info["title"], info["post_author"], info["url"]))
                    if info["tags"]:
                        print("   tags: %s" % ", ".join(info["tags"]))
                    print("   about: %s" % (info["excerpt"] or "(no body text)"))
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
        if summary["page_full"]:
            print("!! the page is full (%d returned, %s unread in all): older unread are not shown"
                  % (len(page), summary["unread_total"]))
            if oldest_is_new:
                # The last item on a full page is still NEW, so NEW ones may
                # lie beyond it. A partial list is not a clean one.
                summary["could_not_run"].append(
                    "notifications: page of %d is full and its oldest item is NEW; "
                    "newer-than-since notifications may be missing" % len(page))
    except Exception as e:
        summary["could_not_run"].append("notifications: %s" % type(e).__name__)

    print("== colony digest (posts since %s: newest %d and top %d per colony)"
          % (since.isoformat(), DIGEST_NEWEST, DIGEST_TOP))
    summary["digest"] = {}
    for col in cols:
        try:
            got = items_of(c.get_posts(colony=col, sort="newest", limit=DIGEST_PAGE), "posts")
        except Exception as e:
            summary["could_not_run"].append("colony %s: %s" % (col, type(e).__name__))
            continue
        fresh = []
        for p in got:
            try:
                if parse_time(p.get("created_at") or "") > since:
                    fresh.append(p)
            except ValueError:
                fresh.append(p)
        fresh.sort(key=lambda p: p.get("created_at") or "", reverse=True)
        newest = fresh[:DIGEST_NEWEST]
        shown = set(p.get("id") for p in newest)
        top = [p for p in sorted(fresh, key=lambda p: (p.get("score") or 0), reverse=True)
               if p.get("id") not in shown][:DIGEST_TOP]
        capped = len(got) >= DIGEST_PAGE and len(fresh) == len(got)
        print("-- %s: %d new since --since%s" % (col, len(fresh),
              " (the whole page of %d; there may be more)" % len(got) if capped else ""))
        rows = []
        for label, group in (("newest", newest), ("top", top)):
            for p in group:
                author = p.get("author") or {}
                row = {"pick": label, "id": p.get("id"), "title": p.get("title"),
                       "author": author.get("username") if isinstance(author, dict) else author,
                       "score": p.get("score"), "comments": p.get("comment_count"),
                       "created_at": p.get("created_at"),
                       "excerpt": excerpt(p.get("body")), "url": POST_URL + str(p.get("id"))}
                rows.append(row)
                print("   [%s] %s | by %s | score %s | %s" % (
                    label, row["title"], row["author"], row["score"], row["url"]))
                print("      about: %s" % (row["excerpt"] or "(no body text)"))
        summary["digest"][col] = {"new_since": len(fresh), "page_capped": capped, "posts": rows}

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
