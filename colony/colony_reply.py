#!/usr/bin/env python3
"""colony/colony_reply.py -- the Colony read's one write path: replies, new-thread comments and upvotes, capped and read back.

    COLONY_API_KEY=... COLONY_SDK_NO_TOKEN_CACHE=1 \
      python3 colony_reply.py --drafts DRAFTS.json --ledger-dir DIR [--dry-run]
      (--ledger-ids IDS.txt in place of --ledger-dir is the older form)

What the routine may do on The Colony, and nothing else (the operator's
decision of 2026-10-12, W42 line 14):

  - reply to a comment addressed to the account -- its parent is one of our
    comments, or it names @commonwealth -- in a thread where the account
    already has a post or a comment; at most MAX_REPLIES per run;
  - upvote a post or comment in such a thread, never our own; at most
    MAX_UPVOTES per run;
  - leave one top-level comment on someone else's post in a thread where the
    account has no post or comment yet, the routine judging the post worth it;
    at most MAX_NEW_THREAD_COMMENTS per run, and the thread then counts as
    joined (the operator's follow-up of 2026-10-19).

No new post, no downvote, DM, follow, join, edit, tag or profile change: those
have no code path here.

DRAFTS.json is a JSON array the run writes:
  {"kind": "reply",  "post_id": ..., "parent_id": <comment id>, "body": ...}
  {"kind": "comment", "post_id": ..., "body": ...}   (new thread, top level)
  {"kind": "upvote", "post_id": ..., "comment_id": <id, or absent for the post>}

Before any write the script compares every public post and comment of the
account with the ledger's `colony` ids, which the script reads itself from a
read_db out_dir (--ledger-dir: DIR/colony/*.json, else DIR/*.json, taking both
the `colony_id` and the `id` field of every row) or from IDS.txt (--ledger-ids,
one id per line): one public item with no ledger id stops the run before it
writes anything, because a write the record cannot see means the key may be
in other hands. Each draft is then checked against the rules above with the
thread read fresh; a draft that fails a rule is SKIPPED with its reason, never
reshaped. A reply is skipped if one of ours already sits under that parent; a
new-thread comment is skipped if the account is already in the thread. Each
write carries a fixed idempotency key, and each reply or comment is read back
and compared field for field.

Prints one JSON line per draft and a last summary line. Exit 0 when every
draft was written or deliberately skipped, 1 when a write failed or a read-back
differed, 3 when the precheck or a read could not run or found an unrecorded
item (nothing was written), 2 on bad arguments. The key comes from the
environment only and is never printed.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time

BASE = "https://thecolony.ai/api/v1"
ME = "6905ab5f-72d0-4460-a5d7-c898df41a1ca"
HANDLE = "commonwealth"
MAX_REPLIES = 5
MAX_UPVOTES = 10
MAX_NEW_THREAD_COMMENTS = 2
MAX_BODY = 4000
MENTION = re.compile(r"@commonwealth\b", re.I)


def items_of(r, *keys):
    if isinstance(r, dict):
        for k in keys + ("items",):
            if isinstance(r.get(k), list):
                return r[k]
        return []
    return r or []


def is_ours(x):
    a = x.get("author") or {}
    return a.get("id") == ME or a.get("username") == HANDLE


def out(obj):
    print(json.dumps(obj, sort_keys=True))


def key_for(d):
    basis = json.dumps(d, sort_keys=True).encode("utf-8")
    return "commonwealth-routine-%s" % hashlib.sha256(basis).hexdigest()[:24]


def public_ids(c):
    """Every public post and comment of the account, paged until has_more is false."""
    ids = set()
    for path in ("/posts?author_id=%s" % ME, "/users/%s/comments" % ME):
        page = 1
        while True:
            sep = "&" if "?" in path else "?"
            r = c._raw_request("GET", "%s%slimit=100&page=%d" % (path, sep, page))
            got = items_of(r)
            ids.update(x.get("id") for x in got if x.get("id"))
            if not (isinstance(r, dict) and r.get("has_more")) or not got:
                break
            page += 1
            time.sleep(1)
    return ids


def check_reply(d, thread):
    by_id = dict((x.get("id"), x) for x in thread)
    if not any(is_ours(x) for x in thread) and not d.get("_post_is_ours"):
        return "commonwealth has no post or comment in this thread"
    parent = by_id.get(d.get("parent_id"))
    if parent is None:
        return "parent comment not found in the thread"
    if is_ours(parent):
        return "the parent is our own comment"
    grand = by_id.get(parent.get("parent_id"))
    addressed = (grand is not None and is_ours(grand)) or bool(MENTION.search(parent.get("body") or ""))
    if not addressed:
        return "the parent is not addressed to commonwealth (not a reply to us, no @commonwealth)"
    if any(is_ours(x) and x.get("parent_id") == d.get("parent_id") for x in thread):
        return "already replied under this parent"
    body = d.get("body")
    if not isinstance(body, str) or not body.strip():
        return "empty body"
    if len(body) > MAX_BODY:
        return "body longer than %d characters" % MAX_BODY
    return None


def check_comment(d, thread, post):
    if is_ours(post) or any(is_ours(x) for x in thread):
        return "commonwealth is already in this thread: use a reply"
    body = d.get("body")
    if not isinstance(body, str) or not body.strip():
        return "empty body"
    if len(body) > MAX_BODY:
        return "body longer than %d characters" % MAX_BODY
    return None


def ledger_ids_from_dir(path):
    """Every `colony_id` and `id` value of the ledger's colony rows, as read_db saves them."""
    sub = os.path.join(path, "colony")
    base = sub if os.path.isdir(sub) else path
    names = sorted(n for n in os.listdir(base) if n.endswith(".json"))
    if not names:
        raise ValueError("no colony rows under the ledger dir")
    ids = set()
    for n in names:
        with open(os.path.join(base, n), encoding="utf-8") as f:
            row = json.load(f)
        if not isinstance(row, dict):
            raise ValueError("a colony row is not a JSON object")
        if isinstance(row.get("data"), dict) and "colony_id" not in row:
            row = row["data"]
        for k in ("colony_id", "id"):
            v = row.get(k)
            if isinstance(v, str) and v.strip():
                ids.add(v.strip())
    return ids


def check_upvote(d, thread, post):
    if not any(is_ours(x) for x in thread) and not is_ours(post):
        return "commonwealth has no post or comment in this thread"
    if d.get("comment_id"):
        target = next((x for x in thread if x.get("id") == d["comment_id"]), None)
        if target is None:
            return "comment not found in the thread"
    else:
        target = post
    if is_ours(target):
        return "never our own item"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--drafts", required=True)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--ledger-dir", help="a read_db out_dir holding the ledger's colony rows")
    src.add_argument("--ledger-ids", help="one ledger colony id per line (older form)")
    ap.add_argument("--dry-run", action="store_true", help="check everything, write nothing")
    a = ap.parse_args()
    try:
        with open(a.drafts, encoding="utf-8") as f:
            drafts = json.load(f)
        if a.ledger_dir:
            ledger = ledger_ids_from_dir(a.ledger_dir)
        else:
            with open(a.ledger_ids, encoding="utf-8") as f:
                ledger = set(l.strip() for l in f if l.strip())
    except (OSError, ValueError) as e:
        out({"summary": {"status": "could_not_run", "reason": "inputs: %s" % type(e).__name__}})
        return 2
    if not isinstance(drafts, list) or not all(isinstance(d, dict) for d in drafts):
        out({"summary": {"status": "could_not_run", "reason": "drafts is not a JSON array of objects"}})
        return 2
    replies = [d for d in drafts if d.get("kind") == "reply"]
    comments = [d for d in drafts if d.get("kind") == "comment"]
    upvotes = [d for d in drafts if d.get("kind") == "upvote"]
    other = [d for d in drafts if d.get("kind") not in ("reply", "comment", "upvote")]
    if (len(replies) > MAX_REPLIES or len(comments) > MAX_NEW_THREAD_COMMENTS
            or len(upvotes) > MAX_UPVOTES or other):
        out({"summary": {"status": "refused",
                         "reason": "over the cap or an unknown kind: %d replies (max %d), %d new-thread comments "
                                   "(max %d), %d upvotes (max %d), %d other"
                                   % (len(replies), MAX_REPLIES, len(comments), MAX_NEW_THREAD_COMMENTS,
                                      len(upvotes), MAX_UPVOTES, len(other))}})
        return 2
    key = os.environ.get("COLONY_API_KEY", "")
    if not key:
        out({"summary": {"status": "could_not_run", "reason": "COLONY_API_KEY is empty or unset"}})
        return 3
    from colony_sdk import ColonyClient
    c = ColonyClient(key, base_url=BASE, cache_token=False)

    try:
        public = public_ids(c)
    except Exception as e:
        out({"summary": {"status": "could_not_run", "reason": "precheck read: %s" % type(e).__name__}})
        return 3
    unrecorded = sorted(public - ledger)
    if unrecorded:
        out({"summary": {"status": "stopped", "reason": "public items with no ledger row; nothing written",
                         "unrecorded": unrecorded}})
        return 3

    threads, posts = {}, {}
    written, skipped, failed = 0, 0, 0
    for d in replies + comments + upvotes:
        pid = d.get("post_id")
        try:
            if pid not in threads:
                threads[pid] = c.get_all_comments(pid)
                p = c.get_post(pid)
                posts[pid] = p.get("post", p)
        except Exception as e:
            out({"kind": d.get("kind"), "post_id": pid, "status": "COULD NOT READ", "error": type(e).__name__})
            failed += 1
            continue
        thread, post = threads[pid], posts[pid]
        if d["kind"] == "reply":
            d["_post_is_ours"] = is_ours(post)
            why = check_reply(d, thread)
            d.pop("_post_is_ours", None)
        elif d["kind"] == "comment":
            why = check_comment(d, thread, post)
        else:
            why = check_upvote(d, thread, post)
        k = key_for(d)
        if why:
            out({"kind": d["kind"], "post_id": pid, "target": d.get("parent_id") or d.get("comment_id"),
                 "status": "SKIP", "reason": why})
            skipped += 1
            continue
        if a.dry_run:
            out({"kind": d["kind"], "post_id": pid, "target": d.get("parent_id") or d.get("comment_id"),
                 "status": "WOULD WRITE", "key": k})
            continue
        try:
            if d["kind"] in ("reply", "comment"):
                parent = d["parent_id"] if d["kind"] == "reply" else None
                res = c.create_comment(pid, d["body"], parent_id=parent, idempotency_key=k)
                cid = (res or {}).get("id")
                back = (c.get_comment(cid) if cid else {}) or {}
                back = back.get("comment", back)
                checks = {"body": back.get("body") == d["body"], "post_id": back.get("post_id") == pid,
                          "parent_id": back.get("parent_id") == parent}
                ok = all(checks.values())
                out({"kind": d["kind"], "post_id": pid, "parent_id": parent, "id": cid,
                     "created_at": back.get("created_at"), "status": "OK" if ok else "MISMATCH",
                     "checks": checks, "body_sha256": hashlib.sha256(d["body"].encode()).hexdigest()})
                written += ok
                failed += not ok
                # Ours now: a second draft under the same parent, or a second new-thread
                # comment on this post, is skipped; a reply in this thread is now allowed.
                threads[pid] = threads[pid] + [dict(back, author={"id": ME, "username": HANDLE})]
            else:
                if d.get("comment_id"):
                    c.vote_comment(d["comment_id"], 1, idempotency_key=k)
                else:
                    c.vote_post(pid, 1, idempotency_key=k)
                out({"kind": "upvote", "post_id": pid, "comment_id": d.get("comment_id"), "status": "OK"})
                written += 1
        except Exception as e:
            out({"kind": d["kind"], "post_id": pid, "status": "FAIL", "error": type(e).__name__,
                 "detail": str(e)[:200]})
            failed += 1
    out({"summary": {"status": "ok" if not failed else "partial", "dry_run": a.dry_run,
                     "replies": len(replies), "comments": len(comments), "upvotes": len(upvotes),
                     "written": written, "skipped": skipped, "failed": failed}})
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
