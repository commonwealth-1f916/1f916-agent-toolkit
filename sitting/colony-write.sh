#!/bin/sh
# sitting/colony-write.sh -- an attended sitting's Colony write, launched in a
# terminal on the Mac: one 1Password prompt, a dry run, and the live run only
# when the dry run passed and every draft is ready to write.
#
#   sh colony-write.sh DIR DRAFTS.json LEDGER_DIR [--approve SHA ...]
#
# DIR is the sitting's dated folder (/private/tmp/1f916-YYYY-MM-DD). DRAFTS and
# LEDGER_DIR are colony/colony_session.py's --drafts and --ledger-dir. Each
# --approve SHA is a hash the dry run printed as NEEDS APPROVAL and the
# operator approved; the sitting passes it only after recording that approval.
#
# The script runs colony_session.py from the deployment clone
# (~/Projects/1f916-agent-toolkit), which must be on main and clean, with the
# Python of ~/Projects/colony-commonwealth/.venv. The key's 1Password reference
# is read from ~/.config/1f916/sitting.env (COLONY_KEY_REF), a Mac-local file,
# so no vault reference lives in this repository. The key reaches only the
# child process, through `op run`; it is never printed, written or put in argv.
#
# Writes DIR/colony-dry.PID.out, DIR/colony-live.PID.out (or "live not run")
# and DIR/colony-write.PID.log, whose last line is `VERDICT ...`. A mkdir lock
# stops a second launch of the same window from writing twice.
set -u
[ $# -ge 3 ] || { echo "usage: sh colony-write.sh DIR DRAFTS.json LEDGER_DIR [--approve SHA ...]" >&2; exit 2; }
D=$1; DRAFTS=$2; LEDGER=$3; shift 3
LOG=$D/colony-write.$$.log
mkdir "$D/colony-write.lock" 2>/dev/null || { echo locked > "$D/colony-write-locked.$$.log"; exit 9; }
exec > "$LOG" 2>&1
verdict() { echo "VERDICT $*"; rmdir "$D/colony-write.lock"; exit "${rc:-1}"; }
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
TK=$HOME/Projects/1f916-agent-toolkit
PY=$HOME/Projects/colony-commonwealth/.venv/bin/python
CONF=$HOME/.config/1f916/sitting.env
rc=2
[ -f "$CONF" ] || verdict "FAIL no $CONF"
# shellcheck disable=SC1090
. "$CONF"
[ -n "${COLONY_KEY_REF:-}" ] || verdict "FAIL COLONY_KEY_REF not set in $CONF"
[ "$(git -C "$TK" rev-parse --abbrev-ref HEAD)" = main ] || verdict "FAIL deployment clone is not on main"
[ -z "$(git -C "$TK" status --porcelain)" ] || verdict "FAIL deployment clone is not clean"
S=$TK/colony/colony_session.py
[ -f "$S" ] || verdict "FAIL no colony_session.py at $(git -C "$TK" rev-parse --short HEAD)"
[ -f "$DRAFTS" ] || verdict "FAIL no drafts file"
[ -d "$LEDGER" ] || verdict "FAIL no ledger dir"
echo "toolkit $(git -C "$TK" rev-parse HEAD)"
shasum -a 256 "$S" "$DRAFTS"
"$PY" -c 'import colony_sdk; print("colony-sdk", colony_sdk.__version__)'
APPROVE=''
while [ $# -gt 0 ]; do
  if [ "$1" != --approve ] || [ $# -lt 2 ]; then verdict "FAIL bad argument $1"; fi
  case "$2" in *[!0-9a-f]*|'') verdict "FAIL approval is not a sha-256 hex" ;; esac
  [ ${#2} -eq 64 ] || verdict "FAIL approval is not a sha-256 hex"
  APPROVE="$APPROVE --approve $2"; shift 2
done
DRY=$D/colony-dry.$$.out
LIVE=$D/colony-live.$$.out
export COLONY_SDK_NO_TOKEN_CACHE=1 PY S DRAFTS LEDGER APPROVE DRY LIVE
# One op run, so one prompt. APPROVE holds only checked hex hashes and flags.
# The child's variables expand in the child, on purpose.
# shellcheck disable=SC2016
COLONY_API_KEY=$COLONY_KEY_REF op run -- /bin/sh -c '
  # shellcheck disable=SC2086
  "$PY" "$S" --drafts "$DRAFTS" --ledger-dir "$LEDGER" --dry-run $APPROVE > "$DRY" 2>&1
  d=$?; echo "dry_exit=$d" >> "$DRY"
  if [ $d -eq 0 ] && grep -q "\"WOULD WRITE\"" "$DRY" && ! grep -q "\"NEEDS APPROVAL\"" "$DRY"; then
    # shellcheck disable=SC2086
    "$PY" "$S" --drafts "$DRAFTS" --ledger-dir "$LEDGER" $APPROVE > "$LIVE" 2>&1
    echo "live_exit=$?" >> "$LIVE"
  else
    echo "live not run" > "$LIVE"
  fi'
rc=$?
echo "op_exit=$rc"
tail -n 2 "$DRY"; tail -n 2 "$LIVE"
if grep -q '^live_exit=0$' "$LIVE"; then rc=0; verdict "PASS live run wrote; read $LIVE"; fi
grep -q '^live not run$' "$LIVE" && { rc=1; verdict "HELD the live run did not start; read $DRY"; }
rc=1; verdict "FAIL the live run reported a failure; read $LIVE"
