#!/bin/sh
# sitting/keycheck-hc.sh -- a bridged daily sitting's opening checks
# (docs/daily-sitting.md step 1; docs/bridged-sittings.md (g);
# queue/prompt-batch-2026-W48 line 34).
#
#   sh keycheck-hc.sh DIR
#
# DIR is the sitting's dated folder, named 1f916-YYYY-MM-DD. Runs
# `1f916-gate key-check` under one op run, which signs, compares and sends
# nothing, then sitting/hc-status.sh DIR, the read-only healthchecks read.
# The 1Password reference is read from ~/.config/1f916/sitting.env
# (GATE_ITEM_REF), a Mac-local file, so no vault reference lives in this
# repository; the credential exists only inside op run's child.
#
# Writes DIR/keycheck.log: the deployment clone's commit, branch and dirty
# count, the gate's verdict lines, key_check_exit, op_exit and hc_exit. It
# replaces the script each sitting used to copy from the day before and edit
# with sed, so the hash ghostty-tab.sh checks is this reviewed file's.
# GATE and HC_STATUS override the two programs, for tests only.
set -u
[ $# -eq 1 ] || { echo "usage: sh keycheck-hc.sh DIR" >&2; exit 2; }
D=$1
case "${D##*/}" in
  1f916-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) echo "keycheck-hc: DIR must be a dated folder named 1f916-YYYY-MM-DD" >&2; exit 2 ;;
esac
[ -d "$D" ] || { echo "keycheck-hc: no such folder: $D" >&2; exit 2; }
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
TK=$(cd "$(dirname "$0")/.." && pwd)
GATE=${GATE:-$HOME/bin/1f916-gate}
HC_STATUS=${HC_STATUS:-$TK/sitting/hc-status.sh}
ENVF=$HOME/.config/1f916/sitting.env
LOG=$D/keycheck.log
[ -r "$ENVF" ] || { echo "keycheck-hc: cannot read $ENVF" > "$LOG"; exit 3; }
# shellcheck disable=SC1090
. "$ENVF"
[ -n "${GATE_ITEM_REF:-}" ] || { echo "keycheck-hc: GATE_ITEM_REF unset in sitting.env" > "$LOG"; exit 3; }
{
  echo "toolkit $(git -C "$TK" rev-parse HEAD) branch $(git -C "$TK" rev-parse --abbrev-ref HEAD) dirty=$(git -C "$TK" status --porcelain | wc -l | tr -d ' ')"
  I=$GATE_ITEM_REF
  BEARER=$I/bearer ED25519_PRIV=$I/ed25519_priv HANDLE=$I/handle CITIZEN=$I/citizen GATE=$GATE \
    op run -- /bin/sh -c '"$GATE" key-check; echo "key_check_exit=$?"'
  echo "op_exit=$?"
} > "$LOG" 2>&1
sh "$HC_STATUS" "$D"
echo "hc_exit=$?" >> "$LOG"
