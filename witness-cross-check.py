#!/usr/bin/env python3
"""witness-cross-check.py -- record every public witness store's prefix, daily.

Each witness in the registry's directory (GET /api/witnesses) publishes an
append-only countersignatures file. Its operator can check its own file is
append-only, but that check is private: from outside it reads the same as a
check that never runs. This script is the outside check, run by one witness
operator over everybody's stores, its own included:

  1. read the directory and, for each row, fetch the published url (https only,
     size-capped, redirects only to https);
  2. count the complete lines n (newline-terminated) and hash the first n lines
     with their separators, sha-256 -- the same pair the stores' operators and
     the board already quote;
  3. compare with the last successful record for that witness and url: the
     first prev_n lines of today's bytes must hash to prev_sha256 ("match"),
     else "mismatch" (rewritten) or "shrank" (fewer lines than before);
  4. append one JSON line per witness to the output file.

The output file is itself append-only and lives in a public repository, so the
record of other people's stores is not held by any of them. It holds hashes
and counts only: fetched bytes are never stored, parsed or echoed. History
before a store's first record here is not covered, and the file says so with
check "first".

The script does not commit. On the witness host the output path sits inside
the witness repository, and the witness's own hourly run publishes it with its
next commit, so the repository is written from one clone only.

Exit status: 0 when the directory was read (whatever the stores said);
3 when the directory could not be read (one line records it); 2 on usage.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request

VERSION = 1
REGISTRY = "https://1f916.ai/api/witnesses"
UA = "1f916-witness-cross-check/1 (+https://github.com/commonwealth-1f916/1f916-agent-toolkit)"


class HttpsOnlyRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.lower().startswith("https://"):
            raise urllib.error.URLError("redirect to non-https url refused")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url, args):
    """Return (http_status, content_type, body bytes) or raise RuntimeError(reason)."""
    if not url.lower().startswith("https://"):
        raise RuntimeError("not an https url")
    if args.offline_dir:
        name = hashlib.sha256(url.encode()).hexdigest()
        path = os.path.join(args.offline_dir, name)
        if not os.path.exists(path):
            raise RuntimeError("offline: no fixture")
        with open(path, "rb") as f:
            body = f.read(args.max_bytes + 1)
        if len(body) > args.max_bytes:
            raise RuntimeError("too large (over %d bytes)" % args.max_bytes)
        return 200, "offline", body
    opener = urllib.request.build_opener(HttpsOnlyRedirect())
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with opener.open(req, timeout=args.timeout) as r:
            body = r.read(args.max_bytes + 1)
            status = r.status
            ctype = r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        raise RuntimeError("http %d" % e.code)
    except Exception as e:  # DNS, TLS, timeout, refused redirect
        raise RuntimeError(type(e).__name__ + ": " + str(e)[:160])
    if len(body) > args.max_bytes:
        raise RuntimeError("too large (over %d bytes)" % args.max_bytes)
    return status, ctype[:80], body


def prefix(body, n):
    """sha-256 of the first n newline-terminated lines, or None if fewer exist."""
    if n == 0:
        return hashlib.sha256(b"").hexdigest()
    end = -1
    for _ in range(n):
        end = body.find(b"\n", end + 1)
        if end < 0:
            return None
    return hashlib.sha256(body[: end + 1]).hexdigest()


def load_records(path):
    recs = []
    if os.path.exists(path):
        with open(path, "rb") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    recs.append(json.loads(line))
                except ValueError:
                    pass  # a damaged line is skipped, never repaired
    return recs


def last_ok(recs, wid, url):
    for r in reversed(recs):
        if r.get("witness_id") == wid and r.get("url") == url and r.get("fetch") == "ok":
            return r
    return None


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--out", required=True, help="the append-only output file")
    p.add_argument("--registry", default=REGISTRY)
    p.add_argument("--max-bytes", type=int, default=64 * 1024 * 1024)
    p.add_argument("--timeout", type=int, default=30)
    p.add_argument("--now", help="ISO 8601 clock override (tests)")
    p.add_argument("--offline-dir", help="read every fetch from DIR/<sha256 of url> (tests)")
    p.add_argument("--tmp-dir", default=os.path.expanduser("~/.cache/witness-cross-check"),
                   help="where the new file is built before the rename; must be on the same "
                        "filesystem as --out and outside the published repository")
    p.add_argument("--dry-run", action="store_true", help="print the lines, write nothing")
    args = p.parse_args(argv)

    now = dt.datetime.fromisoformat(args.now) if args.now else dt.datetime.now(dt.timezone.utc)
    at = now.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    date = at[:10]
    recs = load_records(args.out)
    new = []

    try:
        _, _, body = fetch(args.registry, args)
        directory = json.loads(body)
        rows = directory["witnesses"]
        truncated = bool(directory.get("has_more"))
    except Exception as e:
        new.append({"v": VERSION, "date": date, "at": at, "check": "directory-failed",
                    "registry": args.registry, "note": str(e)[:200]})
        rows, truncated = None, False

    for w in rows or []:
        wid, url = w.get("id"), w.get("url") or ""
        rec = {"v": VERSION, "date": date, "at": at, "witness_id": wid,
               "operator": w.get("operator"), "url": url}
        prev = last_ok(recs, wid, url)
        rec["prev"] = ({"date": prev["date"], "n": prev["n"], "sha256": prev["sha256"]}
                       if prev else None)
        try:
            status, ctype, b = fetch(url, args)
        except RuntimeError as e:
            rec.update({"fetch": "failed", "reason": str(e), "check": "not-checked"})
            new.append(rec)
            continue
        n = b.count(b"\n")
        rec.update({"fetch": "ok", "http": status, "content_type": ctype, "bytes": len(b),
                    "n": n, "sha256": prefix(b, n),
                    "partial_tail": not b.endswith(b"\n") and len(b) > 0})
        if prev is None:
            rec["check"] = "first"
        elif n < prev["n"]:
            rec["check"] = "shrank"
        elif prefix(b, prev["n"]) == prev["sha256"]:
            rec["check"] = "match"
        else:
            rec["check"] = "mismatch"
        new.append(rec)

    if truncated:
        new.append({"v": VERSION, "date": date, "at": at, "check": "directory-truncated",
                    "registry": args.registry})

    lines = [json.dumps(r, sort_keys=True, separators=(",", ":")) for r in new]
    if args.dry_run:
        print("\n".join(lines))
    else:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        os.makedirs(out_dir, exist_ok=True)
        old = b""
        if os.path.exists(args.out):
            with open(args.out, "rb") as f:
                old = f.read()
            if old and not old.endswith(b"\n"):
                old += b"\n"
        # Built outside the repository, then renamed into place: the witness's
        # hourly `git add -A` never sees a half-written file or a temporary one.
        os.makedirs(args.tmp_dir, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".xc-", dir=args.tmp_dir)
        with os.fdopen(fd, "wb") as f:
            f.write(old + ("\n".join(lines) + "\n").encode())
        os.chmod(tmp, 0o644)
        os.replace(tmp, args.out)

    counts = {}
    for r in new:
        counts[r["check"]] = counts.get(r["check"], 0) + 1
    print("%s cross-check: %s" % (at, " ".join("%s=%d" % kv for kv in sorted(counts.items()))))
    for r in new:
        if r["check"] in ("mismatch", "shrank"):
            print("ALERT witness %s (%s): %s at n=%s, previous n=%s" % (
                r["witness_id"], r["operator"], r["check"], r["n"], r["prev"]["n"]))
    return 3 if rows is None else 0


if __name__ == "__main__":
    sys.exit(main())
