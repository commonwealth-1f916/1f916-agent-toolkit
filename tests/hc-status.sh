#!/bin/sh
# tests/hc-status.sh -- sitting/hc-status.py, the reducer behind
# sitting/hc-status.sh. The launcher itself needs op and the network and is
# exercised by a sitting; what is tested here is the claim that matters for a
# secret: a read-write listing's ping URLs (which embed the project's ping key)
# are reported as present and never printed.
set -u
here=$(cd "$(dirname "$0")" && pwd)
P="$here/../sitting/hc-status.py"
fail=0
# expect NAME: the condition passed as the rest of the arguments must hold.
expect() {
  name=$1; shift
  if "$@"; then echo "ok - $name"; else echo "not ok - $name"; fail=1; fi
}
lacks() { if printf '%s\n' "$1" | grep -q "$2"; then return 1; fi; return 0; }
has() { printf '%s\n' "$1" | grep -q "$2"; }

RO='{"checks":[{"name":"1f916-12:00","slug":"1f916-12-00","status":"up","last_ping":"2026-11-19T12:21:12+00:00","next_ping":"2026-11-20T12:00:00+00:00","n_pings":7,"unique_key":"u1"},{"name":"weekly audit","slug":"weekly-audit","status":"new","last_ping":null,"next_ping":null,"n_pings":0,"unique_key":"u2"}]}'
out=$(printf '%s' "$RO" | python3 "$P"); rc=$?
expect "read-only listing exits 0" [ "$rc" = 0 ]
expect "read-only key reported" has "$out" '^key_kind=read-only'
expect "one line per check" [ "$(printf '%s\n' "$out" | grep -c '^check ')" = 2 ]
expect "fields kept" has "$out" 'slug=1f916-12-00 status=up last_ping=2026-11-19T12:21:12+00:00'

SECRET=SPECIMENpingkeyNOTREAL0123456789
RW='{"checks":[{"name":"x","slug":"x","status":"down","last_ping":null,"next_ping":null,"n_pings":0,"ping_url":"https://hc-ping.example/'$SECRET'/x","update_url":"https://healthchecks.example/api/v3/checks/'$SECRET'"}]}'
out=$(printf '%s' "$RW" | python3 "$P"); rc=$?
expect "read-write listing exits 0" [ "$rc" = 0 ]
expect "read-write key reported" has "$out" '^key_kind=READ-WRITE'
expect "no ping URL printed" lacks "$out" "$SECRET"

out=$(printf 'not json %s' "$SECRET" | python3 "$P"); rc=$?
expect "non-JSON exits 3" [ "$rc" = 3 ]
expect "non-JSON input not echoed" lacks "$out" "$SECRET"

out=$(printf '{"error":"wrong api key"}' | python3 "$P"); rc=$?
expect "error body exits 3" [ "$rc" = 3 ]

expect "launcher parses" sh -n "$here/../sitting/hc-status.sh"
if [ "$fail" = 0 ]; then echo "PASSED"; else echo "FAILED"; exit 1; fi
