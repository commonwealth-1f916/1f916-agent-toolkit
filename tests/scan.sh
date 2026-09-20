#!/bin/sh
# tests/scan.sh -- acceptance tests for 1f916-scan.
#
# No secret and no network: the "credential" is the suite's all-zeros dummy
# (the one value tests/hygiene.sh exempts), which has never been anything.
# The tests check the properties the tool exists for: it finds a byte-exact
# copy wherever it is, text or binary; it never reports the pattern file as a
# hit and never prints the pattern; it refuses an empty pattern file rather
# than answering; patterns are bytes, not regexes; and its exit status is the
# verdict.
#
# Usage: tests/scan.sh [path-to-scan]     (default: the tool beside this suite)

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SCAN="${1:-$here/../1f916-scan}"
[ -r "$SCAN" ] || { printf 'tests: scan tool not readable: %s\n' "$SCAN" >&2; exit 1; }

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; n=0
ok()   { n=$((n+1)); pass=$((pass+1)); printf 'ok %d - %s\n' "$n" "$1"; }
nok()  { n=$((n+1)); fail=$((fail+1)); printf 'not ok %d - %s\n' "$n" "$1"
         [ $# -gt 1 ] && printf '  # %s\n' "$2"; }

DUMMY='1f916_sk_0000000000000000000000000000000000000000000000000000000000000000'
DUMMY2='TESTONLY-not-a-key-ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ'

mkdir -p "$WORK/tree/a/b" "$WORK/tree/c" "$WORK/clean"
printf '%s\n' "$DUMMY" >"$WORK/pat.txt"
printf '%s\n%s\n' "$DUMMY" "$DUMMY2" >"$WORK/pat2.txt"
printf 'nothing here\n' >"$WORK/tree/a/plain.txt"
printf 'secret=%s\n' "$DUMMY" >"$WORK/tree/a/b/leak.env"
printf 'prefix %s suffix\n' "$DUMMY2" >"$WORK/tree/c/other.log"
printf '\000\001binary\000%s\000' "$DUMMY" >"$WORK/tree/c/blob.bin"
printf 'clean\n' >"$WORK/clean/x.txt"
: >"$WORK/empty.txt"
printf '\n  \n' >"$WORK/blank.txt"

# 1. a copy is found, named once, exit 1; the pattern file is not a hit
out=$(sh "$SCAN" "$WORK/pat.txt" "$WORK/tree" "$WORK/pat.txt" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'a/b/leak.env' \
   && printf '%s\n' "$out" | grep -q 'c/blob.bin' \
   && ! printf '%s\n' "$out" | grep -q 'pat.txt' \
   && printf '%s\n' "$out" | grep -q 'scan: 2 paths, 2 files matched, 0 unreadable'; then
  ok "finds text and binary copies, names each once, excludes the pattern file, exits 1"
else nok "finds copies" "rc=$rc out=$out"; fi

# 2. the pattern bytes never appear in the output (the tool must not echo them)
if ! printf '%s\n' "$out" | grep -qF "$DUMMY"; then
  ok "never prints the pattern"
else nok "never prints the pattern"; fi

# 3. clean tree: exit 0 and a zero summary
out=$(sh "$SCAN" "$WORK/pat.txt" "$WORK/clean" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = 'scan: 1 paths, 0 files matched, 0 unreadable' ]; then
  ok "clean tree exits 0 with a zero summary"
else nok "clean tree" "rc=$rc out=$out"; fi

# 4. several patterns in one file, each found
out=$(sh "$SCAN" "$WORK/pat2.txt" "$WORK/tree" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'other.log' && printf '%s\n' "$out" | grep -q 'leak.env'; then
  ok "every pattern in the file is searched for"
else nok "multiple patterns" "rc=$rc out=$out"; fi

# 5. an empty or blank pattern file is refused (exit 3), not answered.
#    The MESSAGE is asserted, not just the code: since 2026-09-20 the tool
#    filters blank lines into a working copy, and a filter that emptied the
#    copy would also exit 3 -- by a different route and for a different
#    reason. Two refusals printing the same sentence are two refusals no test
#    can tell apart, and tests/mutants.sh proved it: the mutant that deletes
#    this guard survived the whole suite until the exit code stopped being the
#    only thing checked.
for f in empty.txt blank.txt; do
  out=$(sh "$SCAN" "$WORK/$f" "$WORK/tree" 2>&1); rc=$?
  if [ "$rc" -eq 3 ] && printf '%s\n' "$out" | grep -q 'no pattern in it'; then
    ok "refuses $f with exit 3, naming the pattern file as the reason"
  else nok "refuses $f" "rc=$rc out=$out"; fi
done

# 5b. A REAL PATTERN FOLLOWED BY A BLANK LINE. Test 5 covers a file with no
#     pattern at all, which the tool has refused since it was written; this is
#     the case the runs actually produce, and until 2026-09-20 it was the worst
#     of the three. An empty line is an empty PATTERN and grep -F -f matches
#     every line of every file against it, so the scan named every readable
#     file under every path it was given -- while the header said blank lines
#     were ignored. The daily prompts write this file fresh each day with the
#     Write tool, two values one per line, and one newline too many was all it
#     took. The test is exact rather than "at least one hit": the defect's
#     signature is a file with NO copy in it being named.
printf '%s\n\n' "$DUMMY" >"$WORK/pat-blank.txt"
out=$(sh "$SCAN" "$WORK/pat-blank.txt" "$WORK/tree/a" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'a/b/leak.env' \
   && ! printf '%s\n' "$out" | grep -q 'plain.txt' \
   && printf '%s\n' "$out" | grep -q 'scan: 1 paths, 1 files matched, 0 unreadable'; then
  ok "a trailing blank line in the pattern file does not make every file a hit"
else nok "blank line in the pattern file" "rc=$rc out=$out"; fi

# 5c. and the filtered copy the tool makes of the pattern file is not itself
#     reported as a hit -- it holds the secret, so it would match, and a scan
#     that names its own scratch file is the pattern-file bug with a new name.
#     TMPDIR is pointed at an empty directory and that same directory is
#     scanned, so every temporary the tool makes lands inside the search path
#     and a single match there is the failure. Scanning the real /tmp would
#     have measured this suite's own fixtures instead.
mkdir -p "$WORK/scratch"
out=$(TMPDIR="$WORK/scratch" sh "$SCAN" "$WORK/pat-blank.txt" "$WORK/clean" "$WORK/scratch" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = 'scan: 2 paths, 0 files matched, 0 unreadable' ]; then
  ok "the tool's own filtered copy of the pattern file is never a hit"
else nok "filtered copy excluded" "rc=$rc out=$out"; fi

# 6. no pattern file at all: usage, exit 3
sh "$SCAN" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then ok "no arguments is a usage error"; else nok "usage" "rc=$rc"; fi

# 7. a missing path is counted as unreadable, not silently skipped
out=$(sh "$SCAN" "$WORK/pat.txt" "$WORK/clean" "$WORK/does-not-exist" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = 'scan: 2 paths, 0 files matched, 1 unreadable' ]; then
  ok "a missing path is counted, and the verdict stays honest about it"
else nok "missing path" "rc=$rc out=$out"; fi

# 9. a path that EXISTS but cannot be read is counted too. Test 7 covers the
#    other branch -- a path that is not there at all -- and until 2026-09-14
#    nothing covered this one: the tool counts grep's stderr lines into the
#    same total, and a mutant that stopped doing so survived the whole suite.
#    Root can read anything, so under root this SKIPS AND SAYS SO rather than
#    passing on a condition it never created (same rule as the alert suite on
#    macOS). CI runs unprivileged on both runners, where it executes for real.
if [ "$(id -u)" = "0" ]; then
  printf '# running as root: the unreadable-path test was SKIPPED, not passed\n'
else
  mkdir -p "$WORK/locked/inner"
  printf '%s\n' "$DUMMY" >"$WORK/locked/inner/hidden"
  chmod 000 "$WORK/locked"
  out=$(sh "$SCAN" "$WORK/pat.txt" "$WORK/clean" "$WORK/locked" 2>&1); rc=$?
  chmod 755 "$WORK/locked"
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'scan: 2 paths, 0 files matched, [1-9]'; then
    ok "an unreadable path is counted as unreadable, not silently skipped"
  else nok "unreadable path" "rc=$rc out=$out"; fi
fi

# 8. patterns are bytes, not regexes: a '.' in the pattern must not match anything else
printf 'a.c\n' >"$WORK/pat3.txt"
printf 'abc\n' >"$WORK/clean/abc.txt"
out=$(sh "$SCAN" "$WORK/pat3.txt" "$WORK/clean" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then ok "patterns are fixed strings, not regexes"; else nok "fixed strings" "rc=$rc out=$out"; fi

printf '# scan tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
