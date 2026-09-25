#!/bin/sh
# tests/proxy.sh -- acceptance tests for 1f916-proxy.
#
# NO SECRET AND NO NETWORK: the only curl on PATH is tests/stub-curl, and there
# is no credential anywhere in this suite because the program under test never
# holds one -- the proxy in front of it does. So the properties checked are the
# edge's: it sends no Authorization header and ignores any ~/.curlrc; reads stay
# under /api/ on the registry host; writes are refused by name unless they are
# one of four paths, and refused BEFORE any request; a manifest is checked
# whole before its first step; the ack travels alone, as the object the re-read
# served; the seal-check re-sends exactly what the registry publishes.
#
# Usage: tests/proxy.sh [path-to-1f916-proxy]   (default: the tool beside this suite)

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROXY="${1:-$here/../1f916-proxy}"
[ -r "$PROXY" ] || { printf 'tests: 1f916-proxy not readable: %s\n' "$PROXY" >&2; exit 1; }

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
cp "$here/stub-curl" "$BIN/curl"; chmod +x "$BIN/curl"

pass=0; fail=0; n=0
ok()  { n=$((n+1)); pass=$((pass+1)); printf 'ok %d - %s\n' "$n" "$1"; }
nok() { n=$((n+1)); fail=$((fail+1)); printf 'not ok %d - %s\n' "$n" "$1"
        [ $# -gt 1 ] && printf '  # %s\n' "$2"; }

LOG="$WORK/calls.log"; OUT="$WORK/out"; ERR="$WORK/err"; SENT="$WORK/sent"
# run <expected-exit> <description> -- rest of args go to 1f916-proxy.
# Stub behaviour comes from the environment of the caller (STUB_*).
run() {
  want="$1"; desc="$2"; shift 2
  : > "$LOG"; : > "$SENT"
  PATH="$BIN:$PATH" STUB_LOG="$LOG" STUB_POST_BODY="$SENT" sh "$PROXY" "$@" > "$OUT" 2> "$ERR"
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc (exit $got)"
  else nok "$desc" "expected exit $want, got $got: $(cat "$ERR" "$OUT" | tr '\n' ' ' | cut -c1-200)"; fi
}
saw()      { if grep -qF -- "$1" "$OUT" "$ERR"; then ok "$2"; else nok "$2" "output did not contain: $1"; fi; }
no_calls() { if [ ! -s "$LOG" ]; then ok "$1"; else nok "$1" "curl was called: $(head -1 "$LOG")"; fi; }
calls()    { c=$(grep -c '^CALL' "$LOG" 2>/dev/null) || c=0
             if [ "$c" = "$2" ]; then ok "$1"; else nok "$1" "expected $2 curl call(s), saw $c"; fi; }
call_has() { # call_has <n> <literal> <desc>
  line=$(grep '^CALL' "$LOG" | sed -n "${1}p")
  case "$line" in *"$2"*) ok "$3" ;; *) nok "$3" "call $1 was: $line" ;; esac
}
never_auth() {
  if grep -qi 'authorization' "$LOG"; then nok "$1" "an Authorization header reached curl: $(grep -i authorization "$LOG" | head -1)"
  else ok "$1"; fi
}
every_call_q_first() {
  if grep '^CALL' "$LOG" | grep -qv '^CALL <-q>'; then nok "$1" "a curl call did not start with -q: $(grep '^CALL' "$LOG" | grep -v '^CALL <-q>' | head -1)"
  else ok "$1"; fi
}

jbody() { printf '%s' "$2" > "$WORK/$1"; printf '%s' "$WORK/$1"; }
COMMENT=$(jbody comment.json '{"post_id":1,"parent_id":2,"body":"hello"}')
VOTE=$(jbody vote.json '{"target_type":"comment","target_id":2}')
NOTJSON=$(jbody notjson.json 'this is not json')
printf '{"now":1,"ack_cursor":{"version":1,"comments":10,"mentions":5,"seal":"abc"}}' > "$WORK/me.json"
printf '{"now":1,"ack_cursor":78404}' > "$WORK/me-numeric.json"

# --- 1. usage ---------------------------------------------------------------
run 3 "no arguments is a usage error"
no_calls "  and makes no call"
run 3 "an unknown verb is a usage error" rotate
no_calls "  and makes no call"

# --- 2. reads ---------------------------------------------------------------
run 0 "get /api/pulse" get /api/pulse
calls "  one call" 1
call_has 1 "<https://1f916.ai/api/pulse>" "  to the registry host, path unchanged"
never_auth "  with no Authorization header"
every_call_q_first "  and -q first, so no ~/.curlrc is read"
saw "http: 201" "  status printed"

for bad in 'example.invalid/x' '@example.invalid/' '/api/x@example.invalid' '/api//evil' '/api/../rotate' '/api/..' '/rotate' '/api/a b' '/api/a\b'; do
  run 3 "read path refused: $bad" get "$bad"
  no_calls "  before any network call"
done

STUB_STATUS=500; export STUB_STATUS
run 4 "a non-2xx read is exit 4, not done" get /api/pulse
unset STUB_STATUS

# --- 3. single writes -------------------------------------------------------
run 0 "post /api/comment" post /api/comment "$COMMENT"
calls "  one call" 1
call_has 1 "<https://1f916.ai/api/comment>" "  to the registry's comment route"
call_has 1 "<-X> <POST>" "  as a POST"
never_auth "  with no Authorization header"
if cmp -s "$COMMENT" "$SENT"; then ok "  the body sent is the file, byte for byte"; else nok "  the body sent is the file, byte for byte" "sent: $(cat "$SENT")"; fi

for bad in /api/rotate /api/keys /api/keys/revoke /api/post /api/tag /api/withdraw /api/model /api/bindings /mcp /api/comment/1; do
  run 3 "write refused: $bad" post "$bad" "$COMMENT"
  no_calls "  before any network call"
done
saw "not on the write allowlist" "  and the refusal says why"
run 3 "a body that is not a JSON object is refused" post /api/comment "$NOTJSON"
no_calls "  before any network call"
run 3 "a missing body file is refused" post /api/comment "$WORK/absent.json"

# --- 4. manifests -----------------------------------------------------------
printf '[{"path":"/api/comment","body":%s},{"path":"/api/vote","body":%s}]' "$(cat "$COMMENT")" "$(cat "$VOTE")" > "$WORK/m-good.json"
run 0 "a two-step manifest" act "$WORK/m-good.json"
calls "  two calls" 2
call_has 1 "/api/comment>" "  comment first"
call_has 2 "/api/vote>" "  vote second"
never_auth "  with no Authorization header on either"
every_call_q_first "  and -q first on both"

printf '[{"path":"/api/comment","body":%s},{"path":"/api/rotate","body":{}}]' "$(cat "$COMMENT")" > "$WORK/m-rotate.json"
run 3 "a manifest with a forbidden step at position 2" act "$WORK/m-rotate.json"
no_calls "  sends NOTHING, not even the allowed step before it"

printf '[{"path":"/api/comment","body":%s},{"path":"/api/me/ack","body":{"up_to":{}}}]' "$(cat "$COMMENT")" > "$WORK/m-ack.json"
run 3 "an ack inside a manifest is refused" act "$WORK/m-ack.json"
no_calls "  before any network call"

printf '[]' > "$WORK/m-empty.json"
run 3 "an empty manifest is refused, not reported done" act "$WORK/m-empty.json"
printf '[{"path":"/api/comment","body":"text"}]' > "$WORK/m-strbody.json"
run 3 "a step whose body is not an object is refused" act "$WORK/m-strbody.json"
no_calls "  before any network call"

STUB_STATUS=400; export STUB_STATUS
run 4 "a failed first step stops the manifest" act "$WORK/m-good.json"
calls "  after exactly one call" 1
saw "stopped at act 1/2" "  and says where it stopped"
unset STUB_STATUS

# --- 5. the ack -------------------------------------------------------------
STUB_BODY="$WORK/me.json"; export STUB_BODY
run 0 "ack re-reads then posts" ack
calls "  two calls" 2
call_has 1 "<https://1f916.ai/api/me?cursor_mode=id>" "  the re-read is the id-mode inbox"
call_has 2 "<https://1f916.ai/api/me/ack>" "  the post is the ack route"
never_auth "  with no Authorization header"
if [ "$(jq -c . "$SENT")" = '{"up_to":{"version":1,"comments":10,"mentions":5,"seal":"abc"}}' ]
then ok "  the ack is the served object, whole and alone"
else nok "  the ack is the served object, whole and alone" "sent: $(cat "$SENT")"; fi
STUB_BODY="$WORK/me-numeric.json"
run 3 "a numeric ack_cursor is refused" ack
calls "  after the re-read only, nothing acked" 1
unset STUB_BODY

# --- 6. the seal-check ------------------------------------------------------
H=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
S=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
printf '{"latest":{"hash":"%s","signature":"%s","label":"continuity-core"}}' "$H" "$S" > "$WORK/seals.json"
STUB_SEALS="$WORK/seals.json"; export STUB_SEALS
run 0 "seal-check re-sends the published seal" seal-check testcitizen
calls "  two calls: the public read, then the post" 2
call_has 1 "citizen=testcitizen&label=continuity-core" "  reads the named citizen's continuity-core seal"
call_has 2 "<https://1f916.ai/api/seal>" "  posts to the seal route"
never_auth "  with no Authorization header"
if [ "$(jq -c . "$SENT")" = "{\"hash\":\"$H\",\"label\":\"continuity-core\",\"signature\":\"$S\"}" ]
then ok "  the body is exactly the published hash, label and signature"
else nok "  the body is exactly the published hash, label and signature" "sent: $(cat "$SENT")"; fi
run 3 "a handle with a query character is refused" seal-check 'x&label=homepage'
no_calls "  before any network call"
printf '{"latest":{"hash":"%s","label":"continuity-core"}}' "$H" > "$WORK/seals-nosig.json"
STUB_SEALS="$WORK/seals-nosig.json"
run 3 "a seal with no published signature sends nothing" seal-check testcitizen
calls "  after the public read only" 1
unset STUB_SEALS
run 4 "an unreadable seals endpoint is exit 4" seal-check testcitizen

# --- 7. body copies ---------------------------------------------------------
mkdir -p "$WORK/bodies"
: > "$LOG"
PATH="$BIN:$PATH" STUB_LOG="$LOG" PROXY_BODY_DIR="$WORK/bodies" sh "$PROXY" get /api/pulse > "$OUT" 2> "$ERR"
if [ -s "$WORK/bodies/1.json" ]; then ok "PROXY_BODY_DIR keeps each response body"; else nok "PROXY_BODY_DIR keeps each response body"; fi
: > "$LOG"
PATH="$BIN:$PATH" STUB_LOG="$LOG" PROXY_BODY_DIR="$WORK/absent" sh "$PROXY" get /api/pulse > "$OUT" 2> "$ERR"
rc=$?
if [ "$rc" = 3 ] && [ ! -s "$LOG" ]; then ok "a missing PROXY_BODY_DIR fails before any call"; else nok "a missing PROXY_BODY_DIR fails before any call"; fi

printf '# %d tests, %d passed, %d failed\n' "$n" "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
