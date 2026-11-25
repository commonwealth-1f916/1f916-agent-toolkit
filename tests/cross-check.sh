#!/bin/sh
# tests/cross-check.sh -- witness-cross-check.py against fixtures, no network.
# What it must hold: a store that only appends reads "match"; one that rewrote a
# line it already published reads "mismatch"; one that lost lines reads
# "shrank"; a failed fetch is "not-checked" and is never compared later; the
# output file only ever grows; and no fetched byte reaches the output.
set -u
here=$(cd "$(dirname "$0")" && pwd)
X="$here/../witness-cross-check.py"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fx="$t/fx"; mkdir -p "$fx" "$t/tmp"
fail=0
expect() {
  name=$1; shift
  if "$@"; then echo "ok - $name"; else echo "not ok - $name"; fail=1; fi
}
key() { printf '%s' "$1" | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'; }
put() { printf '%b' "$2" > "$fx/$(key "$1")"; }
lacks_in_text() { if printf '%s\n' "$1" | grep -q "$2"; then return 1; fi; return 0; }
lacks_in() { if grep -q "$2" "$1"; then return 1; fi; return 0; }
says() { printf '%s\n' "$1" | grep -q "$2"; }
grew_from() { [ "$(head -c "$2" "$1" | wc -c | tr -d ' ')" = "$2" ] && [ "$(wc -l < "$1" | tr -d ' ')" = "$3" ]; }
last_has() { tail -1 "$1" | grep -q "$2"; }
REG=https://registry.example/api/witnesses
A=https://a.example/c.jsonl; B=https://b.example/c.jsonl; C=https://c.example/c.jsonl
D=https://d.example/c.jsonl; E=http://e.example/c.jsonl
put "$REG" '{"witnesses":[{"id":1,"operator":"a","url":"'$A'"},{"id":2,"operator":"b","url":"'$B'"},{"id":3,"operator":"c","url":"'$C'"},{"id":4,"operator":"d","url":"'$D'"},{"id":5,"operator":"e","url":"'$E'"}],"has_more":false}'
SECRETISH=FETCHEDBYTESMUSTNOTAPPEAR
put "$A" "{\"l\":1,\"$SECRETISH\":1}\n{\"l\":2}\n"
put "$B" '{"l":1}\n{"l":2}\n'
put "$C" '{"l":1}\n{"l":2}\n{"l":3}\n'
# D has no fixture: its fetch fails.
OUT="$t/out/prefixes.jsonl"
run() { python3 "$X" --out "$OUT" --registry "$REG" --offline-dir "$fx" --tmp-dir "$t/tmp" --now "$1"; }
col() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
  r=json.loads(l)
  if r.get("date")==sys.argv[2] and r.get("witness_id")==int(sys.argv[3]): print(r[sys.argv[4]])' "$OUT" "$@"; }

run 2026-11-22T12:37:00+00:00 >/dev/null; rc=$?
expect "day 1 exits 0" [ "$rc" = 0 ]
expect "day 1 writes one line per witness" [ "$(wc -l < "$OUT" | tr -d ' ')" = 5 ]
expect "day 1 A first" [ "$(col 2026-11-22 1 check)" = first ]
expect "day 1 A n=2" [ "$(col 2026-11-22 1 n)" = 2 ]
expect "day 1 D fetch failed" [ "$(col 2026-11-22 4 fetch)" = failed ]
expect "day 1 E http refused" [ "$(col 2026-11-22 5 reason)" = "not an https url" ]
expect "no fetched byte in output" lacks_in "$OUT" "$SECRETISH"
expect "no temporary file left" [ -z "$(ls -A "$t/tmp")" ]
size1=$(wc -c < "$OUT" | tr -d ' ')

# Day 2: A appends, B rewrites line 2, C loses a line, D now serves.
put "$A" "{\"l\":1,\"$SECRETISH\":1}\n{\"l\":2}\n{\"l\":3}\n{\"l\":4"
put "$B" '{"l":1}\n{"l":"two"}\n{"l":3}\n'
put "$C" '{"l":1}\n{"l":2}\n'
put "$D" '{"l":1}\n'
out=$(run 2026-11-23T12:37:00+00:00); rc=$?
expect "day 2 exits 0" [ "$rc" = 0 ]
expect "file only grew" grew_from "$OUT" "$size1" 10
expect "day 2 A match" [ "$(col 2026-11-23 1 check)" = match ]
expect "day 2 A counts complete lines only" [ "$(col 2026-11-23 1 n)" = 3 ]
expect "day 2 A partial tail flagged" [ "$(col 2026-11-23 1 partial_tail)" = True ]
expect "day 2 B mismatch" [ "$(col 2026-11-23 2 check)" = mismatch ]
expect "day 2 C shrank" [ "$(col 2026-11-23 3 check)" = shrank ]
expect "day 2 D first (failed day not a baseline)" [ "$(col 2026-11-23 4 check)" = first ]
expect "alert printed for B" says "$out" '^ALERT witness 2 (b): mismatch'
expect "alert printed for C" says "$out" '^ALERT witness 3 (c): shrank'

# Day 3: B compared against its last ok record (day 2), not day 1.
out=$(run 2026-11-24T12:37:00+00:00)
expect "day 3 B match against day 2" [ "$(col 2026-11-24 2 check)" = match ]

# A directory that cannot be read: one line, exit 3.
rm "$fx/$(key "$REG")"
run 2026-11-25T12:37:00+00:00 >/dev/null; rc=$?
expect "directory failure exits 3" [ "$rc" = 3 ]
expect "directory failure recorded" last_has "$OUT" directory-failed

# The prefix hash agrees with an independent computation (head -n | sha256).
want=$(printf '{"l":1}\n{"l":2}\n' | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
expect "prefix hash is sha-256 of the first n lines" [ "$(col 2026-11-22 2 sha256)" = "$want" ]

# HTML index pages (queue/task-2026-11-24-cross-check-html-rows). F links its
# store by a relative <link rel=alternate type=application/jsonl>; G has no such
# link; H's link leads off the host. A record of F's page taken before the rule
# (v1, url = the page) must never be the baseline for the store.
REG2=https://registry2.example/api/witnesses
F=https://f.example/; FS=https://f.example/countersignatures.jsonl
G=https://g.example/; H=https://h.example/; HS=https://evil.example/c.jsonl
put "$REG2" '{"witnesses":[{"id":9,"operator":"f","url":"'$F'"},{"id":10,"operator":"g","url":"'$G'"},{"id":11,"operator":"h","url":"'$H'"}],"has_more":false}'
put "$F" '<!DOCTYPE html>\n<html><head>\n<link rel="icon" href="favicon.svg">\n<link rel="alternate" type="application/jsonl" href="countersignatures.jsonl" title="every line">\n</head><body>page</body></html>\n'
put "$FS" '{"l":1}\n{"l":2}\n'
put "$G" '<html><head><title>no store here</title></head><body>x</body></html>\n'
put "$H" '<!doctype html><link type="application/jsonl" rel="alternate" href="'$HS'">\n'
put "$HS" '{"l":1}\n'
OUT2="$t/out2/prefixes.jsonl"; mkdir -p "$t/out2"
old_page_sha=$(key "$(printf '<!DOCTYPE html>\n<html><head>\n')")
printf '{"v":1,"date":"2026-11-23","at":"2026-11-23T08:37:00Z","witness_id":9,"operator":"f","url":"%s","fetch":"ok","http":200,"content_type":"text/html","bytes":200,"n":5,"sha256":"%s","partial_tail":false,"prev":null,"check":"first"}\n' "$F" "$old_page_sha" > "$OUT2"
run2() { python3 "$X" --out "$OUT2" --registry "$REG2" --offline-dir "$fx" --tmp-dir "$t/tmp" --now "$1"; }
col2() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
  r=json.loads(l)
  if r.get("date")==sys.argv[2] and r.get("witness_id")==int(sys.argv[3]): print(r.get(sys.argv[4]))' "$OUT2" "$@"; }
out=$(run2 2026-11-24T12:37:00+00:00); rc=$?
expect "html day exits 0" [ "$rc" = 0 ]
expect "F resolved to its store" [ "$(col2 2026-11-24 9 resolved_url)" = "$FS" ]
expect "F counted the store, not the page" [ "$(col2 2026-11-24 9 n)" = 2 ]
expect "F old page record is not the baseline" [ "$(col2 2026-11-24 9 check)" = first ]
expect "F no false rewrite alert" lacks_in_text "$out" "ALERT witness 9"
expect "G page without a store link not-checked" [ "$(col2 2026-11-24 10 check)" = not-checked ]
expect "G reason names the missing link" [ "$(col2 2026-11-24 10 reason)" = "html page with no application/jsonl alternate link" ]
expect "H off-host link not-checked" [ "$(col2 2026-11-24 11 reason)" = "jsonl alternate leads off the host" ]
put "$FS" '{"l":1}\n{"l":2}\n{"l":3}\n'
run2 2026-11-25T12:37:00+00:00 >/dev/null
expect "F next day matches its own store" [ "$(col2 2026-11-25 9 check)" = match ]
expect "F next day prev is the store record" [ "$(col2 2026-11-25 9 prev | grep -c "'n': 2")" = 1 ]

if [ "$fail" = 0 ]; then echo "PASSED"; else echo "FAILED"; exit 1; fi
