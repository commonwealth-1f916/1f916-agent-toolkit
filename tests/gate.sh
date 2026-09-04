#!/bin/sh
# tests/gate.sh -- acceptance tests for 1f916-gate.
#
# NO SECRET AND NO NETWORK. Every credential here is a dummy; the only host the
# suite can reach is a shell script. That is the point: the eight acceptance
# tests recorded in this project's operating spec were run by hand against the
# live registry, which meant they were run once, by their author, on one machine.
#
# Method: the gate is not modified for testability. A REGISTRY the environment
# could redirect would be a way to make the gate send the bearer to a host of
# the caller's choosing -- the precise property the gate exists to deny. So the
# double is placed on PATH instead (tests/stub-curl), outside the program.
#
# Usage: tests/gate.sh [path-to-gate]     (default: the gate beside this suite)
#
# Exit 0 if every test passes, 1 otherwise.

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
GATE="${1:-$here/../1f916-gate}"
[ -r "$GATE" ] || { printf 'tests: gate not readable: %s\n' "$GATE" >&2; exit 1; }

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
cp "$here/stub-curl" "$BIN/curl"
chmod +x "$BIN/curl"

# Dummy credentials. The seed is 32 bytes of a fixed pattern so the signature is
# reproducible; it has never been a key for anything.
D_BEARER='1f916_sk_0000000000000000000000000000000000000000000000000000000000000000'
D_SEED=$(printf 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZQ' | cut -c1-43)
D_HANDLE='testcitizen'
D_CITIZEN='999'

pass=0; fail=0; n=0
ok()   { n=$((n+1)); pass=$((pass+1)); printf 'ok %d - %s\n' "$n" "$1"; }
nok()  { n=$((n+1)); fail=$((fail+1)); printf 'not ok %d - %s\n' "$n" "$1"
         [ $# -gt 1 ] && printf '  # %s\n' "$2"; }

# run <expected-exit> <description> -- rest of args go to the gate.
# Credentials come from the environment of this function, never from argv.
LOG="$WORK/calls.log"
OUT="$WORK/out"; ERR="$WORK/err"
run() {
  want="$1"; desc="$2"; shift 2
  : > "$LOG"
  PATH="$BIN:$PATH" STUB_LOG="$LOG" \
  BEARER="$D_BEARER" ED25519_PRIV="$D_SEED" HANDLE="$D_HANDLE" CITIZEN="$D_CITIZEN" \
    sh "$GATE" "$@" > "$OUT" 2> "$ERR"
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc (exit $got)"
  else nok "$desc" "expected exit $want, got $got: $(cat "$ERR" "$OUT" | tr '\n' ' ' | cut -c1-160)"; fi
}
saw()      { if grep -qF -- "$1" "$OUT" "$ERR"; then ok "$2"; else nok "$2" "output did not contain: $1"; fi; }
no_calls() { if [ ! -s "$LOG" ]; then ok "$1"; else nok "$1" "curl was called: $(head -1 "$LOG")"; fi; }
calls()    { c=$(grep -c '^CALL' "$LOG" 2>/dev/null || echo 0)
             if [ "$c" = "$2" ]; then ok "$1"; else nok "$1" "expected $2 curl call(s), saw $c"; fi; }
no_secret_in_argv() {
  if grep -qF -- "$D_BEARER" "$LOG" 2>/dev/null
  then nok "$1" "the bearer appeared in curl's argv"
  else ok "$1"; fi
}

printf '# 1f916-gate acceptance tests\n# gate: %s\n' "$GATE"

# Before anything runs: prove the double is the curl these tests will reach.
# A suite that quietly falls back to the real one would make live calls while
# reporting the same "ok" lines, which is the failure this project keeps filing.
assert_double() {  # assert_double <bindir> <label>
  if [ ! -f "$1/curl" ]; then nok "$2: the curl double is missing" "no $1/curl"; return; fi
  if head -n 3 "$1/curl" | grep -q 'Test double for curl'; then ok "$2: the curl double is in place"
  else nok "$2: the curl double is in place" "$1/curl is not the stub"; fi
}
assert_double "$BIN" "0. main PATH"

# ---------------------------------------------------------------- refuse first
# The whole guard is exercisable with dummy values because the gate refuses on
# empty inputs BEFORE any network call. A checker that produces output in the
# failure world is the defect this project spends its time filing about.

: > "$LOG"
env -i PATH="$BIN:$PATH" STUB_LOG="$LOG" sh "$GATE" seal-check > "$OUT" 2> "$ERR"
got=$?
if [ "$got" = 3 ]; then ok "1. no inputs at all -> exit 3"
else nok "1. no inputs at all -> exit 3" "got $got"; fi
for v in BEARER ED25519_PRIV HANDLE CITIZEN; do saw "$v" "1. names the missing input $v"; done
no_calls "1. no network call was made"

# A REAL body file: the gate checks the body exists before it checks the
# allowlist, so passing /dev/null (a character device, not a regular file)
# stops the run one step early and tests the wrong thing.
echo '{"body":"present"}' > "$WORK/real-body.json"

run 3 "2. off-allowlist path is refused"        post /api/admin "$WORK/real-body.json"
saw "not on the write allowlist" "2. the refusal names the allowlist"
saw "/api/admin" "2. and names the path"
run 3 "3. /api/rotate is refused by name"       post /api/rotate "$WORK/real-body.json"
saw "/api/rotate" "3. the refusal names /api/rotate"

# Tests 4-6 are the acceptance test for the 2026-09-03 allowlist extension:
# each new path must pass the allowlist and fail at the NEXT check, which is
# what proves it was added to the list and not to some earlier branch.
run 3 "4. /api/porch/knock reaches the body check" post /api/porch/knock "$WORK/nope.json"
saw "body file not found" "4. and fails there, not at the allowlist"
run 3 "5. /api/withdraw reaches the body check"    post /api/withdraw "$WORK/nope.json"
saw "body file not found" "5. and fails there, not at the allowlist"
run 3 "6. /api/model reaches the body check"       post /api/model "$WORK/nope.json"
saw "body file not found" "6. and fails there, not at the allowlist"

run 3 "7. unknown verb is refused"              frobnicate
saw "usage" "7. and the usage line is printed"
run 3 "7b. get with no path is refused"         get
run 3 "7c. post with no body argument is refused" post /api/comment

# ------------------------------------------------------- the gate's own compare
# The registry serves a hash that cannot match dummy credentials, so this is the
# WRONG-CREDENTIAL case: it must stop at exit 2 with no authenticated call at
# all. Aimed at a newly added allowlist path on purpose, so it proves the new
# routes sit BEHIND the gate rather than beside it.
printf '{"latest":{"hash":"%s","signature":"deadbeef"}}' \
  "0000000000000000000000000000000000000000000000000000000000000000" > "$WORK/seals-wrong.json"
echo '{"model":"test"}' > "$WORK/body.json"

STUB_SEALS="$WORK/seals-wrong.json"; export STUB_SEALS
run 2 "8. valid shape, wrong credential -> MISMATCH" post /api/model "$WORK/body.json"
saw "MISMATCH" "8. and says so"
saw "Credentials NOT used" "8. and says the credentials were not used"
calls "8. exactly one call was made (the unauthenticated seals GET)" 1
no_secret_in_argv "8. the bearer never appeared in curl's argv"

run 2 "8b. seal-check with a wrong credential also stops at the compare" seal-check
calls "8b. again exactly one call, and it is unauthenticated" 1

# ------------------------------------------------------- registry-side failures
# 'Could not run' and 'ran and found nothing wrong' are different cells and the
# gate never collapses them.
unset STUB_SEALS
run 3 "9. an unreachable seals endpoint is 'gate did not run'" seal-check
saw "could not fetch" "9. and says which step failed"

printf 'not json at all' > "$WORK/seals-bad.json"
STUB_SEALS="$WORK/seals-bad.json"; export STUB_SEALS
run 3 "10. an unparseable seals response is 'gate did not run'" seal-check
saw "could not parse" "10. and says which field failed"

# ------------------------------------------------------------ the key arm
# A matching hash lets the run reach the signature comparison. The suite
# computes the expected hash and signature the same way the gate does, so the
# happy path is genuinely exercised rather than asserted.
# Detected, not assumed: sha256sum is GNU, shasum is perl/macOS, and a suite
# that hardcodes either is the same portability bug it is here to test for.
if command -v sha256sum >/dev/null 2>&1; then SHA='sha256sum'; else SHA='shasum -a 256'; fi
h=$(printf '1f916 continuity core v1\nhandle=%s\ncitizen=%s\nsecret=%s\ned25519_priv=%s\n' \
  "$D_HANDLE" "$D_CITIZEN" "$D_BEARER" "$D_SEED" | $SHA | cut -d' ' -f1)
sig=$(ED25519_PRIV="$D_SEED" node -e '
  const c = require("crypto");
  const seed = Buffer.from(process.env.ED25519_PRIV, "base64url");
  const der = Buffer.concat([Buffer.from("302e020100300506032b657004220420","hex"), seed]);
  const key = c.createPrivateKey({ key: der, format: "der", type: "pkcs8" });
  process.stdout.write(c.sign(null, Buffer.from(process.argv[1],"utf8"), key).toString("base64url"));
' "1f916.seal.v1:${D_HANDLE}:continuity-core:${h}" 2>/dev/null)

if [ -z "$sig" ]; then
  printf '# node unavailable or signing failed; skipping the key-arm tests\n'
else
  printf '{"latest":{"hash":"%s","signature":"%s"}}' "$h" "$sig" > "$WORK/seals-good.json"
  STUB_SEALS="$WORK/seals-good.json"; export STUB_SEALS

  run 0 "11. key-check passes when the key reproduces the published signature" key-check
  saw "nothing sent" "11. and sends nothing"
  calls "11. exactly one call, the unauthenticated seals GET" 1

  run 0 "12. seal-check files the row when hash and key both agree" seal-check
  calls "12. two calls: the seals GET and the POST" 2

  printf '{"latest":{"hash":"%s","signature":"%s"}}' "$h" "AAAA${sig}" > "$WORK/seals-badsig.json"
  STUB_SEALS="$WORK/seals-badsig.json"; export STUB_SEALS
  run 5 "13. hash matches but the key does not -> exit 5, its own cell" seal-check
  saw "KEY MISMATCH" "13. and says so"
  calls "13. no authenticated call was made" 1

  # A registry that answers after a passing gate is a different failure again.
  STUB_SEALS="$WORK/seals-good.json"; export STUB_SEALS
  STUB_STATUS=500; export STUB_STATUS
  run 4 "14. a non-2xx after a passing gate is exit 4, not exit 3" seal-check
  saw "500" "14. and reports the status"
  unset STUB_STATUS
  STUB_NET_FAIL=1; export STUB_NET_FAIL
  run 4 "15. a network failure after a passing gate is exit 4" seal-check
  unset STUB_NET_FAIL
fi

# ------------------------------------------- the 2026-09-02 review's remainder
# Every assertion below was watched go red against the gate as it stood before
# the change that added it; tests/mutants.sh keeps that true.

# Item 4 -- a body the gate can see but cannot use.
printf 'this is not json' > "$WORK/notjson.json"
unset STUB_SEALS
run 3 "16. a body file that is not JSON is refused before any network call" post /api/comment "$WORK/notjson.json"
saw "not valid JSON" "16. and says so rather than letting the registry say 400"
no_calls "16. and no network call was made"

if [ "$(id -u)" = "0" ]; then
  printf '# running as root: skipping the unreadable-body test, since root ignores the mode\n'
else
  cp "$WORK/real-body.json" "$WORK/noread.json"; chmod 000 "$WORK/noread.json"
  run 3 "17. an unreadable body file is refused" post /api/comment "$WORK/noread.json"
  saw "not readable" "17. and distinguishes unreadable from absent"
  chmod 644 "$WORK/noread.json"
fi

# Item 5 -- neither digest tool present. The gate must say so and stop, not
# compute an empty hash and compare it against the registry.
# CAUTION, and it bit once: build this directory by symlinking the REAL tools,
# but NEVER symlink curl -- `cp` follows a symlink and writes to its target, so
# `ln -s /usr/bin/curl $NOSHA/curl` followed by `cp stub $NOSHA/curl`
# OVERWRITES THE SYSTEM CURL. It did, in the container this suite was written
# in, which ran as root. On a non-root host the `cp` fails instead and the
# symlink survives, which is worse: the double is gone, the gate makes a REAL
# call to the live registry, and the "no network" claim in the README quietly
# stops being true. Copy the stub in first, and assert it.
NOSHA="$WORK/nosha"; mkdir -p "$NOSHA"
cp "$here/stub-curl" "$NOSHA/curl"; chmod +x "$NOSHA/curl"
for c in jq node sed cut env sh; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$NOSHA/$c"
done
assert_double "$NOSHA" "18. reduced PATH"
: > "$LOG"
env -i PATH="$NOSHA" STUB_LOG="$LOG" \
  BEARER="$D_BEARER" ED25519_PRIV="$D_SEED" HANDLE="$D_HANDLE" CITIZEN="$D_CITIZEN" \
  sh "$GATE" seal-check > "$OUT" 2> "$ERR"
got=$?
if [ "$got" = 3 ]; then ok "18. no sha256sum and no shasum -> exit 3"
else nok "18. no sha256sum and no shasum -> exit 3" "got $got"; fi
saw "neither sha256sum nor shasum" "18. and names what is missing"
no_calls "18. and made no network call"

# Item 6 -- a redirect must never be able to downgrade the scheme that carries
# the bearer, and the handle must not go into a query string raw.
STUB_SEALS="$WORK/seals-wrong.json"; export STUB_SEALS
run 2 "19. still stops at the compare (setup for the flag checks)" seal-check
if grep -q -- "--proto" "$LOG"; then ok "19. curl was called with --proto"
else nok "19. curl was called with --proto" "no --proto in: $(head -1 "$LOG")"; fi
if grep -q -- "<=https>" "$LOG"; then ok "19. and the scheme is pinned to https"
else nok "19. and the scheme is pinned to https" "$(head -1 "$LOG")"; fi

: > "$LOG"
PATH="$BIN:$PATH" STUB_LOG="$LOG" \
  BEARER="$D_BEARER" ED25519_PRIV="$D_SEED" HANDLE='a b/c' CITIZEN="$D_CITIZEN" \
  sh "$GATE" seal-check > "$OUT" 2> "$ERR"
if grep -q 'citizen=a%20b%2Fc' "$LOG"; then ok "20. a handle with reserved characters is percent-encoded"
else nok "20. a handle with reserved characters is percent-encoded" "$(head -1 "$LOG")"; fi

# Item 3 -- the registry's response is scanned before it is printed. The old
# comment justified printing it with a claim about what the far side does.
if [ -n "$sig" ]; then
  STUB_SEALS="$WORK/seals-good.json"; export STUB_SEALS
  printf '{"ok":true,"echo":"%s"}' "$D_BEARER" > "$WORK/leaky.json"
  STUB_BODY="$WORK/leaky.json"; export STUB_BODY
  run 4 "21. a response containing the credential is withheld" seal-check
  saw "response withheld" "21. and says why"
  if grep -qF -- "$D_BEARER" "$OUT" "$ERR"
  then nok "21. and the credential itself is not printed" "the gate printed it"
  else ok "21. and the credential itself is not printed"; fi
  unset STUB_BODY

  # Item 8 -- curl succeeding while printing no status at all.
  STUB_NO_STATUS=1; export STUB_NO_STATUS
  run 4 "22. no HTTP status after a passing gate is named, not fallen through" seal-check
  saw "no HTTP status" "22. and says which fact is missing"
  unset STUB_NO_STATUS
fi

printf '# %d tests, %d passed, %d failed\n' "$n" "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
