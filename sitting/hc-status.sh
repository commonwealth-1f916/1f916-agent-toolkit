#!/bin/sh
# sitting/hc-status.sh -- a bridged sitting's read of the healthchecks.io
# project's checks (docs/daily-sitting.md step 2.1; queue/prompt-batch-2026-W48
# line 16).
#
#   sh hc-status.sh DIR
#
# One GET of https://healthchecks.io/api/v3/checks/ with the project's
# READ-ONLY API key, reduced by sitting/hc-status.py to each check's name,
# slug, status, last_ping, next_ping and n_pings, and whether the key is
# read-only. The 1Password reference is read from ~/.config/1f916/sitting.env
# (HC_READ_REF), a Mac-local file, so no vault reference lives in this
# repository. The key exists only inside op run's child and reaches curl on
# stdin (-H @-), never in argv and never in a file; the raw response is piped
# to the parser and never written to disk. A read-write key is reported
# (key_kind READ-WRITE) and its ping URLs are not printed.
#
# Writes DIR/hc-status.PID.log ending `VERDICT ...`. Reads only; nothing is
# retried.
set -u
[ $# -eq 1 ] || { echo "usage: sh hc-status.sh DIR" >&2; exit 2; }
D=$1
LOG=$D/hc-status.$$.log
exec > "$LOG" 2>&1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
TK=$HOME/Projects/1f916-agent-toolkit
CONF=$HOME/.config/1f916/sitting.env
[ -f "$CONF" ] || { echo "VERDICT FAIL no $CONF"; exit 2; }
# shellcheck disable=SC1090
. "$CONF"
[ -n "${HC_READ_REF:-}" ] || { echo "VERDICT FAIL HC_READ_REF not set in $CONF"; exit 2; }
echo "toolkit $(git -C "$TK" rev-parse HEAD)"
export TK
# The child's variables expand in the child, on purpose.
# shellcheck disable=SC2016
HC_API_KEY=$HC_READ_REF op run -- /bin/sh -c '
  printf "X-Api-Key: %s\n" "$HC_API_KEY" |
    curl -q -sS -m 20 -H @- -w "%{stderr}HTTP %{http_code}\n" https://healthchecks.io/api/v3/checks/ |
    python3 "$TK/sitting/hc-status.py"'
rc=$?
if [ "$rc" = 0 ]; then echo "VERDICT PASS"; else echo "VERDICT FAIL exit $rc"; fi
exit "$rc"
