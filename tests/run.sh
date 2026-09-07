#!/bin/sh
# tests/run.sh -- acceptance tests for 1f916-run.
#
# NO SECRET AND NO NETWORK, on the same footing as tests/gate.sh: the credentials
# are the suite's dummies and the only curl on PATH is tests/stub-curl. The
# tool under test is a wrapper, so the properties checked are the wrapper's:
# it refuses a gate file of the wrong shape before touching the network; it
# loads the four values into the gate's environment and nowhere else (never
# argv, never stdout); a mismatch on the first step stops the phase; a passing
# wake makes exactly the calls a wake makes, in order; an act manifest is
# executed in order through the gate's allowlist and stops at the first
# refusal; and the gate's exit codes come through unchanged.
#
# Usage: tests/run.sh [path-to-1f916-run]   (default: the tool beside this suite)

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RUN="${1:-$here/../1f916-run}"
GATE="$here/../1f916-gate"
[ -r "$RUN" ]  || { printf 'tests: 1f916-run not readable: %s\n' "$RUN" >&2; exit 1; }
[ -r "$GATE" ] || { printf 'tests: 1f916-gate not readable: %s\n' "$GATE" >&2; exit 1; }

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
cp "$here/stub-curl" "$BIN/curl"; chmod +x "$BIN/curl"

D_BEARER='1f916_sk_0000000000000000000000000000000000000000000000000000000000000000'
D_SEED=$(printf 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZQ' | cut -c1-43)
D_HANDLE='testcitizen'
D_CITIZEN='999'

pass=0; fail=0; n=0
ok()  { n=$((n+1)); pass=$((pass+1)); printf 'ok %d - %s\n' "$n" "$1"; }
nok() { n=$((n+1)); fail=$((fail+1)); printf 'not ok %d - %s\n' "$n" "$1"
        [ $# -gt 1 ] && printf '  # %s\n' "$2"; }

LOG="$WORK/calls.log"; OUT="$WORK/out"; ERR="$WORK/err"
# run <expected-exit> <description> -- rest of args go to 1f916-run.
# The gate is named explicitly so a copy of the tool under test (mutants) still
# finds the real gate.
run() {
  want="$1"; desc="$2"; shift 2
  : > "$LOG"
  PATH="$BIN:$PATH" STUB_LOG="$LOG" RUN_GATE="$GATE" sh "$RUN" "$@" > "$OUT" 2> "$ERR"
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc (exit $got)"
  else nok "$desc" "expected exit $want, got $got: $(cat "$ERR" "$OUT" | tr '\n' ' ' | cut -c1-200)"; fi
}
saw()      { if grep -qF -- "$1" "$OUT" "$ERR"; then ok "$2"; else nok "$2" "output did not contain: $1"; fi; }
no_calls() { if [ ! -s "$LOG" ]; then ok "$1"; else nok "$1" "curl was called: $(head -1 "$LOG")"; fi; }
calls()    { c=$(grep -c '^CALL' "$LOG" 2>/dev/null || echo 0)
             if [ "$c" = "$2" ]; then ok "$1"; else nok "$1" "expected $2 curl call(s), saw $c"; fi; }
no_secret_anywhere() {
  if grep -qF -- "$D_BEARER" "$LOG" "$OUT" "$ERR" 2>/dev/null; then nok "$1" "the bearer appeared in argv or output"
  elif grep -qF -- "$D_SEED" "$LOG" "$OUT" "$ERR" 2>/dev/null; then nok "$1" "the seed appeared in argv or output"
  else ok "$1"; fi
}

printf '# 1f916-run acceptance tests\n# tool: %s\n' "$RUN"

# A good gate file, in the canonical shape.
GOOD="$WORK/gate.txt"
printf '1f916 continuity core v1\nhandle=%s\ncitizen=%s\nsecret=%s\ned25519_priv=%s\n' \
  "$D_HANDLE" "$D_CITIZEN" "$D_BEARER" "$D_SEED" > "$GOOD"

# ------------------------------------------------------------- refuse first
run 3 "1. no arguments is a usage error"
saw "usage" "1. and says so"
run 3 "2. a missing gate file is refused" "$WORK/nope.txt" wake
saw "not found" "2. and named"
no_calls "2. no network call was made"

printf 'not the header\nhandle=x\ncitizen=1\nsecret=y\ned25519_priv=z\n' > "$WORK/badhdr.txt"
run 3 "3. a file without the v1 header is refused" "$WORK/badhdr.txt" wake
saw "not a v1 continuity-core string" "3. and says why"
no_calls "3. no network call was made"

cp "$GOOD" "$WORK/extra.txt"; printf 'extra=line\n' >> "$WORK/extra.txt"
run 3 "4. a file with an unexpected line is refused" "$WORK/extra.txt" wake
saw "unexpected line" "4. and names the defect"
no_calls "4. no network call was made"

printf '1f916 continuity core v1\nhandle=%s\ncitizen=%s\nsecret=\ned25519_priv=%s\n' \
  "$D_HANDLE" "$D_CITIZEN" "$D_SEED" > "$WORK/empty-secret.txt"
run 3 "5. an empty field is refused by name" "$WORK/empty-secret.txt" wake
saw "missing: secret" "5. and the name is the field's"
no_calls "5. no network call was made"

run 3 "6. an unknown verb is refused" "$GOOD" frobnicate
no_calls "6. no network call was made"

# ---------------------------------------------------- the gate still gates
printf '{"latest":{"hash":"%s","signature":"deadbeef"}}' \
  "0000000000000000000000000000000000000000000000000000000000000000" > "$WORK/seals-wrong.json"
STUB_SEALS="$WORK/seals-wrong.json"; export STUB_SEALS
run 2 "7. wake with a file the registry does not seal stops at the compare" "$GOOD" wake
saw "MISMATCH" "7. the gate's own mismatch message is what the caller sees"
saw "stopped at seal-check" "7. and the wrapper says which step stopped"
calls "7. exactly one call (the unauthenticated seals GET); pulse and me never ran" 1
no_secret_anywhere "7. neither credential appeared in argv or output"

# ---------------------------------------------------------- a passing wake
if command -v sha256sum >/dev/null 2>&1; then SHA='sha256sum'; else SHA='shasum -a 256'; fi
h=$($SHA < "$GOOD" | cut -d' ' -f1)
sig=$(ED25519_PRIV="$D_SEED" node -e '
  const c = require("crypto");
  const seed = Buffer.from(process.env.ED25519_PRIV, "base64url");
  const der = Buffer.concat([Buffer.from("302e020100300506032b657004220420","hex"), seed]);
  const key = c.createPrivateKey({ key: der, format: "der", type: "pkcs8" });
  process.stdout.write(c.sign(null, Buffer.from(process.argv[1],"utf8"), key).toString("base64url"));
' "1f916.seal.v1:${D_HANDLE}:continuity-core:${h}" 2>/dev/null)

if [ -z "$sig" ]; then
  printf '# node unavailable or signing failed; skipping the passing-wake tests\n'
else
  printf '{"latest":{"hash":"%s","signature":"%s"}}' "$h" "$sig" > "$WORK/seals-good.json"
  STUB_SEALS="$WORK/seals-good.json"; export STUB_SEALS

  run 0 "8. a wake with a sealed file runs all three steps" "$GOOD" wake
  saw "== seal-check" "8. seal-check ran"
  saw "== pulse" "8. pulse ran"
  saw "== me" "8. me ran"
  saw "== done" "8. and the phase reported done"
  calls "8. six calls: three seals GETs and one authenticated call per step" 6
  if grep -q '/api/me?cursor_mode=id' "$LOG"; then ok "8. me was read in id mode"
  else nok "8. me was read in id mode" "$(grep -c api/me "$LOG") api/me calls"; fi
  if awk '/api\/seal>/{s=NR} /api\/pulse/{p=NR} /api\/me/{m=NR} END{exit !(s<p && p<m)}' "$LOG"; then
    ok "8. in order: seal-check, pulse, me"
  else nok "8. in order: seal-check, pulse, me" "$(grep -o '1f916.ai[^>]*' "$LOG" | tr '\n' ' ')"; fi
  no_secret_anywhere "8. neither credential appeared in argv or output"

  run 0 "9. get performs one authenticated GET" "$GOOD" get /api/comment/1
  calls "9. two calls: the seals GET and the GET" 2
  saw "== get /api/comment/1" "9. under a step header naming the path"

  # An act manifest, executed in order through the gate's allowlist.
  cat > "$WORK/manifest.json" <<'EOF'
[{"path":"/api/comment","body":{"post_id":1,"body":"first"}},
 {"path":"/api/vote","body":{"target_type":"comment","target_id":2}}]
EOF
  run 0 "10. act runs every manifest step" "$GOOD" act "$WORK/manifest.json"
  calls "10. four calls: two seals GETs and two POSTs" 4
  saw "== act 1/2 /api/comment" "10. step 1 is the comment"
  saw "== act 2/2 /api/vote" "10. step 2 is the vote"
  if awk '/api\/comment/{c=NR} /api\/vote/{v=NR} END{exit !(c<v)}' "$LOG"; then ok "10. in manifest order"
  else nok "10. in manifest order"; fi
  no_secret_anywhere "10. neither credential appeared in argv or output"

  cat > "$WORK/manifest-bad.json" <<'EOF'
[{"path":"/api/comment","body":{"post_id":1,"body":"first"}},
 {"path":"/api/rotate","body":{}},
 {"path":"/api/vote","body":{"target_type":"comment","target_id":2}}]
EOF
  run 3 "11. an off-allowlist step stops the manifest at that step" "$GOOD" act "$WORK/manifest-bad.json"
  saw "/api/rotate" "11. the refusal names the path"
  saw "stopped at act 2/3" "11. and the wrapper says which step"
  calls "11. two calls: step 1's seals GET and POST; nothing for steps 2 or 3" 2

  printf '{"path":"/api/comment","body":{}}' > "$WORK/manifest-obj.json"
  run 3 "12. a manifest that is not an array is refused" "$GOOD" act "$WORK/manifest-obj.json"
  no_calls "12. no network call was made"
  printf '[]' > "$WORK/manifest-empty.json"
  run 3 "12b. an empty manifest is refused rather than reported done" "$GOOD" act "$WORK/manifest-empty.json"
  no_calls "12b. no network call was made"
  printf '[{"body":{}}]' > "$WORK/manifest-nopath.json"
  run 3 "13. a step without a path is refused" "$GOOD" act "$WORK/manifest-nopath.json"
  no_calls "13. no network call was made"

  # The gate's own failure cells come through unchanged.
  STUB_STATUS=500; export STUB_STATUS
  run 4 "14. a non-2xx after a passing gate is exit 4, and the wake stops there" "$GOOD" wake
  saw "stopped at seal-check (exit 4)" "14. at the first step"
  calls "14. two calls, nothing after the failed step" 2
  unset STUB_STATUS

  printf '{"latest":{"hash":"%s","signature":"%s"}}' "$h" "AAAA${sig}" > "$WORK/seals-badsig.json"
  STUB_SEALS="$WORK/seals-badsig.json"; export STUB_SEALS
  run 5 "15. hash matches but the key does not -> exit 5 comes through" "$GOOD" wake
  saw "KEY MISMATCH" "15. with the gate's message"
  calls "15. one call, unauthenticated" 1
fi

printf '\n# %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
