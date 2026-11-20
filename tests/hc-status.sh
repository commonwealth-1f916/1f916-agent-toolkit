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
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; fail=1; }

RO='{"checks":[{"name":"1f916-12:00","slug":"1f916-12-00","status":"up","last_ping":"2026-11-19T12:21:12+00:00","next_ping":"2026-11-20T12:00:00+00:00","n_pings":7,"unique_key":"u1"},{"name":"weekly audit","slug":"weekly-audit","status":"new","last_ping":null,"next_ping":null,"n_pings":0,"unique_key":"u2"}]}'
out=$(printf '%s' "$RO" | python3 "$P"); rc=$?
[ "$rc" = 0 ] && ok "read-only listing exits 0" || no "read-only listing exit $rc"
printf '%s\n' "$out" | grep -q '^key_kind=read-only' && ok "read-only key reported" || no "read-only key not reported"
[ "$(printf '%s\n' "$out" | grep -c '^check ')" = 2 ] && ok "one line per check" || no "check line count"
printf '%s\n' "$out" | grep -q 'slug=1f916-12-00 status=up last_ping=2026-11-19T12:21:12+00:00' && ok "fields kept" || no "fields lost"

SECRET=SPECIMENpingkeyNOTREAL0123456789
RW='{"checks":[{"name":"x","slug":"x","status":"down","last_ping":null,"next_ping":null,"n_pings":0,"ping_url":"https://hc-ping.example/'$SECRET'/x","update_url":"https://healthchecks.example/api/v3/checks/'$SECRET'"}]}'
out=$(printf '%s' "$RW" | python3 "$P"); rc=$?
[ "$rc" = 0 ] && ok "read-write listing exits 0" || no "read-write listing exit $rc"
printf '%s\n' "$out" | grep -q '^key_kind=READ-WRITE' && ok "read-write key reported" || no "read-write key not reported"
printf '%s\n' "$out" | grep -q "$SECRET" && no "a ping URL was printed" || ok "no ping URL printed"

out=$(printf 'not json %s' "$SECRET" | python3 "$P"); rc=$?
[ "$rc" = 3 ] && ok "non-JSON exits 3" || no "non-JSON exit $rc"
printf '%s\n' "$out" | grep -q "$SECRET" && no "non-JSON input echoed" || ok "non-JSON input not echoed"

out=$(printf '{"error":"wrong api key"}' | python3 "$P"); rc=$?
[ "$rc" = 3 ] && ok "error body exits 3" || no "error body exit $rc"

sh -n "$here/../sitting/hc-status.sh" && ok "launcher parses" || no "launcher does not parse"
[ "$fail" = 0 ] && echo "PASSED" || { echo "FAILED"; exit 1; }
