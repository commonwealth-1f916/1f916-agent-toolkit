#!/usr/bin/env python3
"""colony/colony_session.py -- an attended sitting's write path on The Colony: replies, comments, upvotes and posts.

    COLONY_API_KEY=... COLONY_SDK_NO_TOKEN_CACHE=1 \
      python3 colony_session.py --drafts DRAFTS.json --ledger-dir DIR [--dry-run] [--approve SHA ...]

This is the sitting's tool, not the routine's. The scheduled Colony read
writes only through colony_reply.py, whose rules are narrower; this script is
run by hand from an attended sitting, under `op run` with a person at the
1Password prompt (docs/colony.md, "Sittings write through colony_session.py").

What a sitting may write here:

  reply    {"kind": "reply", "post_id", "parent_id", "body"}
           a reply under someone else's comment, in a thread where the
           account has a post or a comment, or under a comment that names
           @commonwealth. Never under our own comment, never twice under one
           parent.
  comment  {"kind": "comment", "post_id", "body"}
           a top-level comment. In a thread the account has joined (our post,
           or a comment of ours) it is pre-authorized; in any other thread it
           needs the operator's approval of the exact text (below).
  upvote   {"kind": "upvote", "post_id", "comment_id"?}
           an upvote on a post, or on a comment when comment_id is given;
           never our own item.
  post     {"kind": "post", "colony", "title", "body", "post_type"?, "metadata"?}
           a new top-level post in the named colony. Always needs the
           operator's approval. The colony is required: from colony-sdk 1.38
           a post with no colony goes to no colony at all. post_type is one of
           POST_TYPES (default discussion); a finding or an analysis carries
           the metadata the platform asks for (`{"confidence", "sources",
           "tags"}` for a finding). Polls, paid tasks and human requests have
           no code path here.

No downvote, edit, delete, DM, follow, join, tag or profile change: those have
no code path here.

Approval. A draft that needs the operator's approval is written only when its
approval hash is passed with --approve. The hash is the sha-256 of the draft's
canonical JSON (approval_sha256 below: kind, colony, post_type, title, body,
metadata, post_id, parent_id, sorted keys, UTF-8), so it binds the exact text. The dry run
prints it with status NEEDS APPROVAL; the sitting shows the operator that text,
records his approval in the ledger with the hash, and passes the hash to the
live run. A changed byte gives a different hash, and the draft is refused.

Before any write the script compares every public post and comment of the
account with the ledger's `colony` ids (--ledger-dir, a read_db out_dir, or
--ledger-ids) exactly as colony_reply.py does, and stops, writing nothing, if
one is unrecorded. A draft that breaks a rule is SKIPPED with its reason,
never reshaped. Each write carries a fixed idempotency key
("commonwealth-session-<sha24>"); each reply, comment or post is read back
and compared field for field.

Caps per run: MAX_REPLIES replies, MAX_COMMENTS comments, MAX_UPVOTES upvotes,
MAX_POSTS posts. Prints one JSON line per draft and a summary line. Exit 0 when
every draft was written, deliberately skipped, or (dry run) would be written;
1 when a write failed or a read-back differed; 3 when the precheck or a read
could not run or found an unrecorded item (nothing was written); 2 on bad
arguments or over a cap. The key comes from the environment only and is never
printed.
"""
import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import colony_reply as R  # noqa: E402  (shared precheck and thread helpers)

MAX_REPLIES = 5
MAX_COMMENTS = 3
MAX_UPVOTES = 10
MAX_POSTS = 1
MAX_TITLE = 300
POST_TYPES = ("discussion", "finding", "question", "analysis")
KINDS = ("reply", "comment", "upvote", "post")


def approval_sha256(d):
    keep = dict((k, d.get(k)) for k in ("kind", "colony", "post_type", "title", "body", "metadata", "post_id", "parent_id"))
    basis = json.dumps(keep, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(basis).hexdigest()


def key_for(d):
    basis = json.dumps(d, sort_keys=True).encode("utf-8")
    return "commonwealth-session-%s" % hashlib.sha256(basis).hexdigest()[:24]


def body_problem(body):
    if not isinstance(body, str) or not body.strip():
        return "empty body"
    if len(body) > R.MAX_BODY:
        return "body longer than %d characters" % R.MAX_BODY
    return None


def joined(thread, post):
    return R.is_ours(post) or any(R.is_ours(x) for x in thread)


def check_reply(d, thread, post):
    by_id = dict((x.get("id"), x) for x in thread)
    parent = by_id.get(d.get("parent_id"))
    if parent is None:
        return "parent comment not found in the thread"
    if R.is_ours(parent):
        return "the parent is our own comment"
    if not joined(thread, post) and not R.MENTION.search(parent.get("body") or ""):
        return "commonwealth has not joined this thread and the parent does not name @commonwealth"
    if any(R.is_ours(x) and x.get("parent_id") == d.get("parent_id") for x in thread):
        return "already replied under this parent"
    return body_problem(d.get("body"))


def check_comment(d, thread, post):
    """Returns (reason or None, needs_approval)."""
    return body_problem(d.get("body")), not joined(thread, post)


def check_upvote(d, thread, post):
    if d.get("comment_id"):
        target = next((x for x in thread if x.get("id") == d["comment_id"]), None)
        if target is None:
            return "comment not found in the thread"
    else:
        target = post
    if R.is_ours(target):
        return "never our own item"
    return None


def check_post(d):
    col = d.get("colony")
    if not isinstance(col, str) or not col.strip():
        return "no colony named (a post with no colony goes to no colony)"
    title = d.get("title")
    if not isinstance(title, str) or not title.strip():
        return "empty title"
    if len(title) > MAX_TITLE:
        return "title longer than %d characters" % MAX_TITLE
    if d.get("post_type", "discussion") not in POST_TYPES:
        return "post_type not one of %s" % ", ".join(POST_TYPES)
    if d.get("metadata") is not None and not isinstance(d.get("metadata"), dict):
        return "metadata is not a JSON object"
    if d.get("post_type") in ("finding", "analysis") and not d.get("metadata"):
        return "a %s needs metadata" % d["post_type"]
    return body_problem(d.get("body"))


def unwrap(r, k):
    r = r or {}
    return r.get(k, r) if isinstance(r.get(k), dict) else r


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--drafts", required=True)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--ledger-dir", help="a read_db out_dir holding the ledger's colony rows")
    src.add_argument("--ledger-ids", help="one ledger colony id per line")
    ap.add_argument("--dry-run", action="store_true", help="check everything, write nothing")
    ap.add_argument("--approve", action="append", default=[], metavar="SHA",
                    help="approval hash of a draft the operator approved (repeatable)")
    a = ap.parse_args()
    approved = set(s.strip().lower() for s in a.approve)
    try:
        with open(a.drafts, encoding="utf-8") as f:
            drafts = json.load(f)
        if a.ledger_dir:
            ledger = R.ledger_ids_from_dir(a.ledger_dir)
        else:
            with open(a.ledger_ids, encoding="utf-8") as f:
                ledger = set(l.strip() for l in f if l.strip())
    except (OSError, ValueError) as e:
        R.out({"summary": {"status": "could_not_run", "reason": "inputs: %s" % type(e).__name__}})
        return 2
    if not isinstance(drafts, list) or not all(isinstance(d, dict) for d in drafts):
        R.out({"summary": {"status": "could_not_run", "reason": "drafts is not a JSON array of objects"}})
        return 2
    by_kind = dict((k, [d for d in drafts if d.get("kind") == k]) for k in KINDS)
    other = [d for d in drafts if d.get("kind") not in KINDS]
    caps = {"reply": MAX_REPLIES, "comment": MAX_COMMENTS, "upvote": MAX_UPVOTES, "post": MAX_POSTS}
    over = [k for k in KINDS if len(by_kind[k]) > caps[k]]
    if over or other:
        R.out({"summary": {"status": "refused", "reason": "over the cap or an unknown kind",
                           "counts": dict((k, len(by_kind[k])) for k in KINDS), "caps": caps,
                           "unknown": len(other)}})
        return 2
    key = os.environ.get("COLONY_API_KEY", "")
    if not key:
        R.out({"summary": {"status": "could_not_run", "reason": "COLONY_API_KEY is empty or unset"}})
        return 3
    from colony_sdk import ColonyClient
    c = ColonyClient(key, base_url=R.BASE, cache_token=False)

    try:
        public = R.public_ids(c)
    except Exception as e:
        R.out({"summary": {"status": "could_not_run", "reason": "precheck read: %s" % type(e).__name__}})
        return 3
    unrecorded = sorted(public - ledger)
    if unrecorded:
        R.out({"summary": {"status": "stopped", "reason": "public items with no ledger row; nothing written",
                           "unrecorded": unrecorded}})
        return 3

    threads, posts = {}, {}
    n = {"written": 0, "would_write": 0, "skipped": 0, "needs_approval": 0, "failed": 0}
    for d in by_kind["post"] + by_kind["reply"] + by_kind["comment"] + by_kind["upvote"]:
        kind, pid = d["kind"], d.get("post_id")
        line = {"kind": kind, "post_id": pid, "target": d.get("parent_id") or d.get("comment_id")}
        needs = False
        if kind == "post":
            why, needs = check_post(d), True
            line = {"kind": kind, "colony": d.get("colony"), "title": d.get("title")}
        else:
            try:
                if pid not in threads:
                    threads[pid] = c.get_all_comments(pid)
                    posts[pid] = unwrap(c.get_post(pid), "post")
            except Exception as e:
                R.out(dict(line, status="COULD NOT READ", error=type(e).__name__))
                n["failed"] += 1
                continue
            thread, post = threads[pid], posts[pid]
            if kind == "reply":
                why = check_reply(d, thread, post)
            elif kind == "comment":
                why, needs = check_comment(d, thread, post)
            else:
                why = check_upvote(d, thread, post)
        if why:
            R.out(dict(line, status="SKIP", reason=why))
            n["skipped"] += 1
            continue
        sha = approval_sha256(d)
        if needs and sha not in approved:
            R.out(dict(line, status="NEEDS APPROVAL", approval_sha256=sha))
            n["needs_approval"] += 1
            continue
        k = key_for(d)
        if a.dry_run:
            R.out(dict(line, status="WOULD WRITE", key=k, approval_sha256=sha if needs else None))
            n["would_write"] += 1
            continue
        try:
            if kind == "post":
                ptype = d.get("post_type", "discussion")
                res = c.create_post(d["title"], d["body"], colony=d["colony"], post_type=ptype,
                                    metadata=d.get("metadata"), idempotency_key=k)
                new_id = unwrap(res, "post").get("id")
                back = unwrap(c.get_post(new_id) if new_id else {}, "post")
                checks = {"title": back.get("title") == d["title"], "body": back.get("body") == d["body"],
                          "colony": d["colony"] in (back.get("colony_name"), back.get("colony_id")),
                          "post_type": back.get("post_type") == ptype, "author": R.is_ours(back)}
                ok = all(checks.values())
                R.out(dict(line, id=new_id, created_at=back.get("created_at"),
                           status="OK" if ok else "MISMATCH", checks=checks, approval_sha256=sha,
                           body_sha256=hashlib.sha256(d["body"].encode()).hexdigest()))
            elif kind in ("reply", "comment"):
                parent = d["parent_id"] if kind == "reply" else None
                res = c.create_comment(pid, d["body"], parent_id=parent, idempotency_key=k)
                cid = (res or {}).get("id")
                back = unwrap(c.get_comment(cid) if cid else {}, "comment")
                checks = {"body": back.get("body") == d["body"], "post_id": back.get("post_id") == pid,
                          "parent_id": back.get("parent_id") == parent}
                ok = all(checks.values())
                R.out(dict(line, parent_id=parent, id=cid, created_at=back.get("created_at"),
                           status="OK" if ok else "MISMATCH", checks=checks,
                           approval_sha256=sha if needs else None,
                           body_sha256=hashlib.sha256(d["body"].encode()).hexdigest()))
                threads[pid] = threads[pid] + [dict(back, author={"id": R.ME, "username": R.HANDLE})]
            else:
                if d.get("comment_id"):
                    c.vote_comment(d["comment_id"], 1, idempotency_key=k)
                else:
                    c.vote_post(pid, 1, idempotency_key=k)
                ok = True
                R.out(dict(line, status="OK"))
            n["written"] += ok
            n["failed"] += not ok
        except Exception as e:
            R.out(dict(line, status="FAIL", error=type(e).__name__, detail=str(e)[:200]))
            n["failed"] += 1
    R.out({"summary": dict(n, status="ok" if not n["failed"] else "partial", dry_run=a.dry_run,
                           counts=dict((k, len(by_kind[k])) for k in KINDS))})
    return 1 if n["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
