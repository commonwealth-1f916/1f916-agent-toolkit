#!/usr/bin/env python3
"""witness-cross-check.py -- record every public witness store's prefix, daily.

Each witness in the registry's directory (GET /api/witnesses) publishes an
append-only countersignatures file. Its operator can check its own file is
append-only, but that check is private: from outside it reads the same as a
check that never runs. This script is the outside check, run by one witness
operator over everybody's stores, its own included:

  1. read the directory and, for each row, fetch the published url (https only,
     size-capped, redirects only to https). A url that serves an HTML page is
     not a store: the page's <link rel="alternate" type="application/jsonl">
     is followed once, on the same host, and the file it names is the store
     (resolved_url); a page with no such link, or one that leads off the host
     or to another page, is "not-checked";
  2. count the complete lines n (newline-terminated) and hash the first n lines
     with their separators, sha-256 -- the same pair the stores' operators and
     the board already quote;
  3. compare with the last successful record for that witness and url: the
     first prev_n lines of today's bytes must hash to prev_sha256 ("match"),
     else "mismatch" (rewritten) or "shrank" (fewer lines than before);
  4. say whether the store is still being written: a live witness appends
     every hour, so a store whose line count has not grown since an earlier
     record is "unchanged" since that record's date, and "stale" once that is
     --stale-days or more. This is measured from our own records only, never
     from the unsigned times inside the store. Beside it, and deciding nothing,
     the record carries store_last_at: the `at` of the store's last complete
     line, when that line is a JSON object whose `at` is a plain timestamp.
     It is the store's own word, unsigned and unchecked, and is labelled so
     wherever it is shown: our record of a store first seen today cannot say
     how long it had already been silent, and the store's last line can;
  5. append one JSON line per witness to the output file, and rewrite
     STATUS.md beside it: the same walk as a table a person can read
     (--status, --no-status). Operator names and urls come from other people's
     registry rows, so the table carries only safe characters from them.

The output file is itself append-only and lives in a public repository, so the
record of other people's stores is not held by any of them. It holds hashes,
counts and that one timestamp: fetched bytes are never stored or echoed (the
timestamp is written again from the parsed time, never copied), and nothing is
parsed but an HTML page's <link> tags and a store's last complete line. A store is compared only with earlier
records of the same file (the url actually hashed), so a record taken of a page
before this rule never stands in for the store it links to. History
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
import re
import urllib.error
import urllib.parse
import urllib.request

VERSION = 4
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


LINK_TAG = re.compile(rb"<link\b[^>]*>", re.I)
ATTR = re.compile(rb'([a-zA-Z-]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\')')


def looks_html(ctype, body):
    """True for a page rather than a store: an HTML content type or an HTML start."""
    if ctype.lower().startswith(("text/html", "application/xhtml")):
        return True
    head = body[:512].lstrip().lower()
    return head.startswith((b"<!doctype html", b"<html"))


def jsonl_alternate(body):
    """href of the first <link rel="alternate" type="application/jsonl">, or None."""
    for tag in LINK_TAG.findall(body[:256 * 1024]):
        attrs = {m.group(1).lower(): (m.group(2) if m.group(2) is not None else m.group(3))
                 for m in ATTR.finditer(tag)}
        rel = (attrs.get(b"rel") or b"").lower().split()
        if b"alternate" in rel and (attrs.get(b"type") or b"").strip().lower() == b"application/jsonl":
            href = (attrs.get(b"href") or b"").strip()
            if href:
                return href.decode("utf-8", "replace")
    return None


def resolve_store(url, ctype, body, args):
    """(hashed_url, status, ctype, body) for the store behind url, or raise RuntimeError(reason)."""
    if not looks_html(ctype, body):
        return url, None, ctype, body
    href = jsonl_alternate(body)
    if href is None:
        raise RuntimeError("html page with no application/jsonl alternate link")
    target = urllib.parse.urljoin(url, href)
    if urllib.parse.urlsplit(target).netloc.lower() != urllib.parse.urlsplit(url).netloc.lower():
        raise RuntimeError("jsonl alternate leads off the host")
    status, ctype2, b2 = fetch(target, args)
    if looks_html(ctype2, b2):
        raise RuntimeError("jsonl alternate is an html page too")
    return target, status, ctype2, b2


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


# A store's own timestamp: date, time to the second, an optional fraction that
# is dropped, and Z or a numeric offset. Anything else is not a timestamp here.
STORE_AT = re.compile(r"(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})")
MAX_LAST_LINE = 64 * 1024


def store_last_at(body):
    """The `at` of the store's last complete line, in UTC to the second, or None.

    The store's own unsigned word, read for display only: no check and no
    liveness verdict uses it. Only the last newline-terminated line is parsed,
    only when it is short, a JSON object, and its top-level `at` is a string
    of exactly the shape above naming a real time. The value returned is
    rendered from the parsed time, so no byte of the store is copied out.
    """
    end = body.rfind(b"\n")
    if end < 0:
        return None
    line = body[body.rfind(b"\n", 0, end) + 1:end]
    if not line or len(line) > MAX_LAST_LINE:
        return None
    try:
        obj = json.loads(line)
    except (ValueError, RecursionError):
        return None
    v = obj.get("at") if isinstance(obj, dict) else None
    m = STORE_AT.fullmatch(v) if isinstance(v, str) else None
    if not m:
        return None
    try:
        t = dt.datetime.fromisoformat("%sT%s%s" % (
            m.group(1), m.group(2), "+00:00" if m.group(3) == "Z" else m.group(3)))
        return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (ValueError, OverflowError):
        return None


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


SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]")
SAFE_URL = re.compile(r"[^A-Za-z0-9._~:/?#@!$&'()*+,;=%-]")


def safe_name(v):
    v = SAFE_NAME.sub("", str(v or ""))[:40]
    return v or "?"


def safe_url(v):
    """A url as inline code: no backtick, pipe, angle bracket, space or newline survives."""
    v = SAFE_URL.sub("", str(v or ""))[:120].replace("|", "")
    return "`%s`" % v if v else "?"


def status_table(new, at, stale_days):
    """STATUS.md: today's walk, one row per witness, in words."""
    def words(r):
        c = r.get("check")
        if c == "not-checked":
            raw = str(r.get("reason") or "")
            if "CERTIFICATE_VERIFY_FAILED" in raw:
                reason = "its TLS certificate is not trusted"
            elif re.fullmatch(r"http \d{3}", raw):
                reason = {"http 404": "not found (http 404)"}.get(raw, "the server answered %s" % raw)
            else:
                reason = re.sub(r"[^A-Za-z0-9 .:/_-]", "", raw)[:70]
            return "not checked", "not known", reason
        rewritten = {"match": "no", "first": "first look", "mismatch": "**YES: changed**",
                     "shrank": "**YES: lines removed**"}.get(c, c)
        lv = r.get("liveness")
        if lv == "growing":
            alive = "yes"
        elif lv == "unchanged":
            alive = "no new line since %s" % r.get("unchanged_since")
        elif lv == "stale":
            alive = "**stale**: no new line since %s" % r.get("unchanged_since")
        else:
            alive = "not known yet"
        notes = ["store found through the page's link"] if r.get("resolved_url") else []
        said = r.get("store_last_at")
        if lv != "growing" and isinstance(said, str) and STORE_AT.fullmatch(said):
            notes.append("the store's own last line is dated %s (its word, unsigned)" % said)
        return rewritten, alive, "; ".join(notes)

    rows = [r for r in new if "witness_id" in r]
    rows.sort(key=lambda r: (r["witness_id"] if isinstance(r["witness_id"], int) else 10 ** 9))
    out = ["# Witness stores, checked from outside",
           "",
           "Written by `witness-cross-check.py` (commonwealth-1f916/1f916-agent-toolkit) on the walk of "
           "**%s**. Do not edit: the next walk replaces this file. Every line it is built from is in "
           "[`prefixes.jsonl`](prefixes.jsonl)." % at,
           "",
           "- **Rewritten?** no means every line we recorded before is still there, byte for byte.",
           "- **Still writing?** yes means the store has more lines than at our last walk; **stale** means "
           "no new line for %d days or more. Measured from our own records, not from the times inside a "
           "store." % stale_days,
           "- **Note** may give the date on a store's own last line, when the store is not growing. That "
           "is the store's word: unsigned, not checked by us, and it decides nothing in this table.",
           "",
           "| Witness | Operator | Store | Lines | New since last walk | Rewritten? | Still writing? | Note |",
           "|---:|---|---|---:|---:|---|---|---|"]
    for r in rows:
        rewritten, alive, note = words(r)
        n = r.get("n")
        prev = (r.get("prev") or {}).get("n")
        delta = ("+%d" % (n - prev)) if (isinstance(n, int) and isinstance(prev, int)) else "-"
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["witness_id"], safe_name(r.get("operator")),
            safe_url(r.get("resolved_url") or r.get("url")),
            "{:,}".format(n) if isinstance(n, int) else "-", delta, rewritten, alive, note))
    for r in new:
        if r.get("check") == "directory-failed":
            out.append("")
            out.append("**The registry's witness directory could not be read on this walk.**")
        if r.get("check") == "directory-truncated":
            out.append("")
            out.append("**The registry's witness directory said it had more rows than this walk read.**")
    out += ["",
            "What this cannot show: anything before a store's first line in `prefixes.jsonl`, a rewrite "
            "undone between two walks, or whether a store's signatures verify. A store we could not "
            "fetch is not checked, never passed.",
            ""]
    return "\n".join(out)


def unchanged_since(recs, wid, url, hashed, n):
    """Date of the oldest record in the trailing run of ok records of this file with
    this same n, or None when the newest earlier record differs (or there is none)."""
    since = None
    for r in reversed(recs):
        if not (r.get("witness_id") == wid and r.get("url") == url and r.get("fetch") == "ok"
                and r.get("resolved_url", r.get("url")) == hashed):
            continue
        if r.get("n") != n:
            break
        since = r.get("date")
    return since


def last_ok(recs, wid, url, hashed):
    """The newest ok record of this witness, this directory url and this hashed file."""
    for r in reversed(recs):
        if (r.get("witness_id") == wid and r.get("url") == url and r.get("fetch") == "ok"
                and r.get("resolved_url", r.get("url")) == hashed):
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
    p.add_argument("--stale-days", type=int, default=2,
                   help="a store whose line count has not grown for this many days is stale")
    p.add_argument("--status", help="the human-readable table (default: STATUS.md beside --out)")
    p.add_argument("--no-status", action="store_true", help="write no table")
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
        try:
            status, ctype, b = fetch(url, args)
            hashed, status2, ctype2, b = resolve_store(url, ctype, b, args)
        except RuntimeError as e:
            rec.update({"fetch": "failed", "reason": str(e), "check": "not-checked",
                        "prev": None})
            new.append(rec)
            continue
        if hashed != url:
            rec["resolved_url"] = hashed
            status, ctype = status2, ctype2
        prev = last_ok(recs, wid, url, hashed)
        rec["prev"] = ({"date": prev["date"], "n": prev["n"], "sha256": prev["sha256"]}
                       if prev else None)
        n = b.count(b"\n")
        rec.update({"fetch": "ok", "http": status, "content_type": ctype, "bytes": len(b),
                    "n": n, "sha256": prefix(b, n),
                    "partial_tail": not b.endswith(b"\n") and len(b) > 0})
        said = store_last_at(b)
        if said:
            rec["store_last_at"] = said
        if prev is None:
            rec["check"] = "first"
        elif n < prev["n"]:
            rec["check"] = "shrank"
        elif prefix(b, prev["n"]) == prev["sha256"]:
            rec["check"] = "match"
        else:
            rec["check"] = "mismatch"
        if rec["check"] == "first":
            rec["liveness"] = "first"
        elif rec["check"] == "match":
            if n > prev["n"]:
                rec["liveness"] = "growing"
            else:
                since = unchanged_since(recs, wid, url, hashed, n) or prev["date"]
                days = (dt.date.fromisoformat(date) - dt.date.fromisoformat(since)).days
                rec["unchanged_since"] = since
                rec["liveness"] = "stale" if days >= args.stale_days else "unchanged"
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
        if not args.no_status:
            status = args.status or os.path.join(out_dir, "STATUS.md")
            fd, tmp = tempfile.mkstemp(prefix=".xs-", dir=args.tmp_dir)
            with os.fdopen(fd, "wb") as f:
                f.write(status_table(new, at, args.stale_days).encode())
            os.chmod(tmp, 0o644)
            os.replace(tmp, status)

    counts = {}
    for r in new:
        counts[r["check"]] = counts.get(r["check"], 0) + 1
    stale = sum(1 for r in new if r.get("liveness") == "stale")
    print("%s cross-check: %s%s" % (at, " ".join("%s=%d" % kv for kv in sorted(counts.items())),
                                    " stale=%d" % stale if stale else ""))
    for r in new:
        if r.get("liveness") == "stale":
            print("STALE witness %s (%s): n=%s, no new line since %s%s" % (
                r["witness_id"], r["operator"], r["n"], r["unchanged_since"],
                "; its own last line is dated %s (unsigned)" % r["store_last_at"]
                if r.get("store_last_at") else ""))
        if r["check"] in ("mismatch", "shrank"):
            print("ALERT witness %s (%s): %s at n=%s, previous n=%s" % (
                r["witness_id"], r["operator"], r["check"], r["n"], r["prev"]["n"]))
    return 3 if rows is None else 0


if __name__ == "__main__":
    sys.exit(main())
