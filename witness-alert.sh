#!/bin/bash
# witness-alert.sh — independent publisher/liveness check for a 1F916 witness row.
#
# DELIBERATELY OUTSIDE $HOME/1f916-witness. Two reasons, both load-bearing:
#   1. run-witness.sh runs `git add -A`, so any file in that directory becomes a
#      PUBLISHED artifact in the witness repo.
#   2. run-witness.sh and its cron line may be inputs to a published seal
#      (e.g. a witness-reference seal) and to a daily reference-integrity check.
#      Neither may be edited without re-sealing. This script touches neither.
#
# Runs on its own cron line at :12, five minutes after the witness at :07.
# Alerts on STATE CHANGE only — once when something breaks, once when it recovers —
# which is the same discipline as the project's BLOCKING tier.

set -u

# ---- SITE CONFIG lives OUTSIDE this file, so the deployed copy is byte-identical
# ---- to the one in the repository and `git status` means what it says. Sourced
# ---- FIRST, before anything is derived, so every value below can be overridden.
CONF="${WITNESS_ALERT_CONF:-$HOME/.witness-alert.conf}"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

REPO="${WITNESS_REPO:-$HOME/1f916-witness}"
TO="${WITNESS_ALERT_TO:-}"
FROM="${WITNESS_ALERT_FROM:-}"
WITNESS_ID="${WITNESS_ID:-}"
STALE_HOURS="${WITNESS_STALE_HOURS:-3}"
LOG_STALE_MINUTES="${WITNESS_LOG_STALE_MINUTES:-90}"
STATE="${WITNESS_ALERT_STATE:-$HOME/.witness-alert.state}"

# WITNESS_ALERT_TEST=1 marks the mail as an exercise AND diverts the state file.
# The divert is the load-bearing half: a forced test that left the real state file
# behind would SUPPRESS the next genuine alarm, because state means "already told".
TESTMODE="${WITNESS_ALERT_TEST:-0}"
[ "$TESTMODE" = "1" ] && STATE="${STATE}.test"

# REFUSE rather than mail into the void. An alarm addressed to nowhere is worse
# than no alarm: it reports success, sends nothing, and looks healthy forever.
# This is the same rule the gate applies to empty credentials -- a checker that
# produces output in the failure world is the defect, not the safeguard.
if [ -z "$TO" ] || [ -z "$FROM" ]; then
  printf 'witness-alert: WITNESS_ALERT_TO / WITNESS_ALERT_FROM unset and no config at %s -- refusing to run, because an alarm with no destination is silence that looks like health.\n' "$CONF" >&2
  exit 3
fi

# Subject label: "witness #N" when the row id is configured, plain "witness" if not.
WLABEL="witness${WITNESS_ID:+ #${WITNESS_ID}}"
HOST="$(hostname -s)"

cd "$REPO" 2>/dev/null || exit 0

problems=""

# --- 1. THE PUBLISHER. This is the 2026-09-01 failure: twelve commits, unpushed. ---
git fetch -q origin 2>/dev/null
ahead=$(git rev-list --count origin/main..main 2>/dev/null || echo "?")
behind=$(git rev-list --count main..origin/main 2>/dev/null || echo "?")
if [ "$ahead" != "0" ] && [ "$ahead" != "?" ]; then
  problems="${problems}UNPUSHED: local main is ${ahead} commit(s) ahead of origin/main"
  [ "$behind" != "0" ] && problems="${problems} and ${behind} behind (DIVERGED — needs fetch+rebase)"
  problems="${problems}.
"
fi

# --- 2. THE WRITER. Catches a dead cron or a crash before the push line. ---
newest=$(tail -n 1 witness-state/countersignatures.jsonl 2>/dev/null \
         | sed -n 's/.*"at":"\([^"]*\)".*/\1/p')
if [ -z "$newest" ]; then
  problems="${problems}UNREADABLE: could not read a timestamp from countersignatures.jsonl.
"
else
  age=$(( ( $(date -u +%s) - $(date -u -d "$newest" +%s 2>/dev/null || echo 0) ) / 60 ))
  if [ "$age" -gt $(( STALE_HOURS * 60 )) ]; then
    problems="${problems}STALE: newest countersignature ${newest} is ${age} minutes old (threshold ${STALE_HOURS}h).
"
  fi
fi

# --- 3. DID THE WITNESS RUN AT ALL? ---
if [ -f witness.log ]; then
  logage=$(( ( $(date -u +%s) - $(stat -c %Y witness.log) ) / 60 ))
  [ "$logage" -gt "$LOG_STALE_MINUTES" ] && problems="${problems}NOT RUNNING: witness.log untouched for ${logage} minutes (cron should write hourly).
"
else
  problems="${problems}NOT RUNNING: witness.log is missing.
"
fi

send() {  # send <subject-tail> <body>
  tag=""; banner=""
  if [ "$TESTMODE" = "1" ]; then
    tag="[TEST]"
    banner="*** FORCED EXERCISE — NOT A REAL OUTAGE. Verify against the published feed before acting. ***

"
  fi
  printf 'From: %s\nTo: %s\nSubject: [1F916]%s %s\n\n%s%s\n' \
    "$FROM" "$TO" "$tag" "$1" "$banner" "$2" | msmtp "$TO"
}

if [ -n "$problems" ]; then
  if [ ! -f "$STATE" ]; then
    send "${WLABEL} needs attention on ${HOST}" \
"$problems
--- git status ---
$(git status -b --porcelain 2>&1)

--- last 5 log lines ---
$(tail -n 5 witness.log 2>&1)

Repair for the UNPUSHED/DIVERGED case:
  cd \"$REPO\" && git fetch origin && git rebase origin/main && git push origin main
Rebase, not merge: the log's linearity is a published property of this row.
Nothing public is rewritten — unpushed commits have never left this machine.

This alert is sent once per incident and once on recovery."
    date -u +%FT%TZ > "$STATE"
  fi
else
  if [ -f "$STATE" ]; then
    send "${WLABEL} recovered on ${HOST}" \
"Publishing again. Nothing outstanding.

Down since: $(cat "$STATE")
Now:        $(date -u +%FT%TZ)
origin/main $(git rev-parse --short origin/main 2>&1)
newest      ${newest:-unknown}"
    rm -f "$STATE"
  fi
fi

exit 0
