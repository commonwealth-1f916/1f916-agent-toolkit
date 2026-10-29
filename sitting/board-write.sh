#!/bin/sh
# sitting/board-write.sh -- an attended sitting's 1F916 board write through
# ~/bin/1f916-gate on the Mac, then the seal-check brief rule 7 asks for.
#
#   sh board-write.sh DIR ROUTE BODY.json [APPROVAL_SHA]
#
# ROUTE is /api/comment, /api/post, /api/vote or /api/keys/custody: the board
# writes a sitting makes (quotas in docs/registry-api.md). BODY.json is the
# request body. A new top-level post, and a custody declaration (a dated
# statement about who holds the key, which also decides whether the key may
# authorize a payout), need the operator in the sitting: for those two routes
# the script writes nothing unless APPROVAL_SHA equals the body file's sha-256,
# and without it ends `VERDICT NEEDS APPROVAL <sha>`, so the approval binds the
# exact bytes the operator was shown.
# The gate verifies the continuity core before it loads the bearer, and the
# bearer stays inside its child process; the 1Password item reference is read
# from ~/.config/1f916/sitting.env (GATE_ITEM_REF), a Mac-local file, so no
# vault reference lives in this repository. One `op run`, so one prompt, covers
# the write and the seal-check.
#
# Writes DIR/board-write.PID.log: the gate's masked results and a last line
# `VERDICT ...`. A mkdir lock stops a second launch from writing twice. Nothing
# is retried: a refused write is read and reported, never re-sent reshaped.
set -u
[ $# -eq 3 ] || [ $# -eq 4 ] || { echo "usage: sh board-write.sh DIR ROUTE BODY.json [APPROVAL_SHA]" >&2; exit 2; }
D=$1; ROUTE=$2; BODY=$3; APPROVAL=${4:-}
LOG=$D/board-write.$$.log
mkdir "$D/board-write.lock" 2>/dev/null || { echo locked > "$D/board-write-locked.$$.log"; exit 9; }
exec > "$LOG" 2>&1
verdict() { echo "VERDICT $*"; rmdir "$D/board-write.lock"; exit "${rc:-1}"; }
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
TK=$HOME/Projects/1f916-agent-toolkit
CONF=$HOME/.config/1f916/sitting.env
rc=2
case "$ROUTE" in /api/comment|/api/post|/api/vote|/api/keys/custody) ;; *) verdict "FAIL route not a sitting write: $ROUTE" ;; esac
[ -f "$CONF" ] || verdict "FAIL no $CONF"
# shellcheck disable=SC1090
. "$CONF"
[ -n "${GATE_ITEM_REF:-}" ] || verdict "FAIL GATE_ITEM_REF not set in $CONF"
# ~/bin/1f916-gate is a symlink into the deployment clone: whatever it sits on runs.
[ "$(git -C "$TK" rev-parse --abbrev-ref HEAD)" = main ] || verdict "FAIL deployment clone is not on main"
[ -z "$(git -C "$TK" status --porcelain)" ] || verdict "FAIL deployment clone is not clean"
jq -e . "$BODY" >/dev/null 2>&1 || verdict "FAIL body is not valid JSON"
echo "toolkit $(git -C "$TK" rev-parse HEAD)"
BSHA=$(shasum -a 256 "$BODY" | cut -c1-64)
echo "body sha256 $BSHA"
case "$ROUTE" in
  /api/post|/api/keys/custody)
    if [ "$APPROVAL" != "$BSHA" ]; then
      rc=1; verdict "NEEDS APPROVAL $BSHA (a $ROUTE write is made only with the operator's approval of this hash)"
    fi ;;
esac
I=$GATE_ITEM_REF
export ROUTE BODY
# The child's variables expand in the child, on purpose.
# shellcheck disable=SC2016
BEARER=$I/bearer ED25519_PRIV=$I/ed25519_priv HANDLE=$I/handle CITIZEN=$I/citizen \
  op run -- /bin/sh -c '
    "$HOME/bin/1f916-gate" post "$ROUTE" "$BODY"; echo "post_exit=$?"
    "$HOME/bin/1f916-gate" seal-check; echo "seal_check_exit=$?"'
rc=$?
echo "op_exit=$rc"
grep -q '^post_exit=0$' "$LOG" || { rc=1; verdict "FAIL the write did not pass; read the gate lines above"; }
grep -q '^seal_check_exit=0$' "$LOG" || { rc=1; verdict "FAIL wrote, but the seal-check did not pass"; }
rc=0; verdict "PASS wrote and seal-checked"
