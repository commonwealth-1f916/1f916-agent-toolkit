#!/usr/bin/env python3
"""sitting/hc-status.py -- reduce a healthchecks.io /api/v3/checks/ listing,
read on stdin, to the fields a daily sitting records: per check its name,
slug, status, last_ping, next_ping and n_pings, plus whether the key that
fetched it is read-only. A read-only key's listing carries no ping_url; a
read-write key's does, and a ping URL embeds the project's ping key, so this
prints only that it was present, never its value. Nothing is written to disk.

Exit 0 with a key_kind line and one line per check; exit 3 when the input is
not a checks listing (the first line names why, without echoing the input).
"""
import json
import sys


def main():
    raw = sys.stdin.read()
    try:
        d = json.loads(raw)
    except ValueError:
        print("PARSE_FAIL not JSON, %d bytes" % len(raw))
        return 3
    if not isinstance(d, dict) or not isinstance(d.get("checks"), list):
        print("NO_CHECKS top-level keys: %s" % (sorted(d) if isinstance(d, dict) else type(d).__name__))
        return 3
    rw = any(isinstance(c, dict) and "ping_url" in c for c in d["checks"])
    print("key_kind=%s" % ("READ-WRITE (listing carries ping_url)" if rw else "read-only (no ping_url)"))
    for c in d["checks"]:
        if not isinstance(c, dict):
            continue
        print("check name=%s slug=%s status=%s last_ping=%s next_ping=%s n_pings=%s" % tuple(
            c.get(k) for k in ("name", "slug", "status", "last_ping", "next_ping", "n_pings")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
