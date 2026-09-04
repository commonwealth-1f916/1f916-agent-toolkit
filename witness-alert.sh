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
#
# Requires: bash, git, msmtp, GNU date (-d), GNU stat (-c), flock (util-linux, only
# when WITNESS_AUTOHEAL=1). Linux-only as written.

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
# Local record of what this script itself could not do (a failed send). Never
# mailed — it exists precisely for the case where mail is what failed.
SELFLOG="${WITNESS_ALERT_LOG:-$HOME/.witness-alert.log}"
# WITNESS_AUTOHEAL=1 lets this script REPAIR the one outage class it can prove
# safe: local main ahead AND behind origin/main (something else pushed to the
# repo, so the writer's hourly push is rejected forever -- the 2026-09-01
# outage, twelve rejected pushes and a feed dark for twelve hours). Default OFF.
# The repair is fetch+rebase+push, and it runs only under every condition in
# autoheal() below; anything unexpected aborts the rebase and alarms as today.
AUTOHEAL="${WITNESS_AUTOHEAL:-0}"
HEALLOG="${WITNESS_AUTOHEAL_LOG:-$HOME/.witness-autoheal.log}"

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

# autoheal <ahead> <behind> -- attempt the fetch+rebase+push repair. Prints one
# line describing the outcome; returns 0 only if origin/main now equals main.
# Every precondition is checked here, not assumed by the caller:
#   - both ahead AND behind (a plain unpushed state is the writer's to retry);
#   - nothing under witness-state/ changed on origin since the fork point: the
#     countersignature file is append-only by the writer alone, and a foreign
#     commit touching it is exactly the thing a human must look at;
#   - no rebase, merge or index operation in progress, and no modified tracked
#     file (ignored files such as witness.log do not count);
#   - an exclusive lock on the checkout so two heals never overlap. NOTE: the
#     hourly writer takes no lock of its own; this runs at :12, five minutes
#     after it, and a rebase of a few commits takes seconds. The lock guards
#     this script against itself, not against the writer -- stated so nobody
#     reads it as more than it is.
# On any failure the rebase is aborted and the tree is left as it was found.
# Rebase, never merge: the log's linearity is a published property of the row,
# and the commits being rebased have never left this machine.
autoheal() {
  ahead_n="$1"; behind_n="$2"
  [ "$AUTOHEAL" = "1" ] || { echo "autoheal off"; return 1; }
  case "$ahead_n$behind_n" in *\?*) echo "autoheal skipped: ahead/behind unknown"; return 1;; esac
  if [ "$ahead_n" -le 0 ] || [ "$behind_n" -le 0 ]; then
    echo "autoheal skipped: not diverged (ahead ${ahead_n}, behind ${behind_n})"; return 1
  fi
  if [ -e .git/rebase-merge ] || [ -e .git/rebase-apply ] || [ -e .git/MERGE_HEAD ] || [ -e .git/index.lock ]; then
    echo "autoheal skipped: a git operation is in progress"; return 1
  fi
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "autoheal skipped: tracked files are modified (the writer may be mid-run)"; return 1
  fi
  foreign=$(git diff --name-only "main...origin/main" -- witness-state/ 2>/dev/null)
  if [ -n "$foreign" ]; then
    echo "autoheal REFUSED: origin/main changed files under witness-state/ ($(printf '%s' "$foreign" | tr '\n' ' ')) -- a human must look"; return 1
  fi
  exec 9>.git/witness-autoheal.lock || { echo "autoheal skipped: cannot open lock"; return 1; }
  if ! flock -n 9; then echo "autoheal skipped: another heal holds the lock"; return 1; fi
  before=$(git rev-parse --short main 2>/dev/null)
  if ! out=$(git rebase origin/main 2>&1); then
    git rebase --abort >/dev/null 2>&1
    echo "autoheal FAILED at rebase (aborted, tree restored): $(printf '%s' "$out" | tail -n 1)"; return 1
  fi
  if ! out=$(git push origin main 2>&1); then
    echo "autoheal FAILED at push (rebased locally, not published): $(printf '%s' "$out" | tail -n 1)"; return 1
  fi
  git fetch -q origin 2>/dev/null
  if [ "$(git rev-parse main)" != "$(git rev-parse origin/main)" ]; then
    echo "autoheal FAILED: main and origin/main still differ after push"; return 1
  fi
  after=$(git rev-parse --short main)
  printf '%s autoheal: rebased %s commit(s) over %s foreign commit(s), %s -> %s, pushed\n' \
    "$(date -u +%FT%TZ)" "$ahead_n" "$behind_n" "$before" "$after" >> "$HEALLOG" 2>/dev/null
  echo "autoheal OK: rebased ${ahead_n} local commit(s) over ${behind_n} foreign commit(s), ${before} -> ${after}, pushed"
  return 0
}

problems=""
newest=""
in_repo=0

# --- 0. IS THE REPO EVEN THERE? A missing or unreadable checkout used to exit 0
#        silently -- health by omission, the exact failure this script exists to
#        catch. Now it is the first problem line, and the git checks are skipped
#        rather than run against nothing.
if cd "$REPO" 2>/dev/null && [ -d .git ]; then
  in_repo=1
else
  problems="${problems}REPO MISSING: ${REPO} is not a readable git checkout.
"
fi

if [ "$in_repo" = "1" ]; then
  # --- 1. THE PUBLISHER. This is the 2026-09-01 failure: twelve commits, unpushed. ---
  # A fetch that fails is itself a publisher problem: without it, ahead/behind are
  # computed against a STALE origin/main and can read 0 while the public feed is
  # frozen. So the fetch result is a fact to report, never swallowed.
  if ! fetch_err=$(git fetch -q origin 2>&1); then
    problems="${problems}FETCH FAILED: cannot see origin, so publisher state is UNKNOWN (${fetch_err:-no error text}).
"
  fi
  ahead=$(git rev-list --count origin/main..main 2>/dev/null || echo "?")
  behind=$(git rev-list --count main..origin/main 2>/dev/null || echo "?")
  healed=""
  if [ "$ahead" != "0" ] && [ "$ahead" != "?" ] && [ "$behind" != "0" ] && [ "$behind" != "?" ] && [ "$AUTOHEAL" = "1" ]; then
    heal_msg=$(autoheal "$ahead" "$behind")
    case "$heal_msg" in
      "autoheal OK"*) healed="$heal_msg" ;;
      *) problems="${problems}AUTOHEAL: ${heal_msg}.
" ;;
    esac
    # Re-measure after any attempt: a heal that rebased but could not push has
    # changed the numbers, and the report below must describe the tree as it is.
    ahead=$(git rev-list --count origin/main..main 2>/dev/null || echo "?")
    behind=$(git rev-list --count main..origin/main 2>/dev/null || echo "?")
  fi
  if [ "$ahead" != "0" ] && [ "$ahead" != "?" ]; then
    problems="${problems}UNPUSHED: local main is ${ahead} commit(s) ahead of origin/main"
    [ "$behind" != "0" ] && problems="${problems} and ${behind} behind (DIVERGED — needs fetch+rebase)"
    # Corroboration the daily prompt asks a human to check by hand: how many times
    # has the writer logged a rejected push? Distinguishes "push is failing" from
    # "push has not run yet".
    pushfails=$(grep -c "push failed" witness.log 2>/dev/null || echo 0)
    problems="${problems}. witness.log records ${pushfails} 'push failed' line(s) in total.
"
  fi

  # --- 2. THE WRITER. Catches a dead cron or a crash before the push line. ---
  newest=$(tail -n 1 witness-state/countersignatures.jsonl 2>/dev/null \
           | sed -n 's/.*"at":"\([^"]*\)".*/\1/p')
  if [ -z "$newest" ]; then
    problems="${problems}UNREADABLE: could not read a timestamp from countersignatures.jsonl.
"
  elif ! newest_epoch=$(date -u -d "$newest" +%s 2>/dev/null); then
    # An unparseable timestamp is its own fact; reporting it as a fifty-year age
    # would be true and misleading.
    problems="${problems}UNPARSEABLE: newest countersignature timestamp '${newest}' did not parse.
"
  else
    age=$(( ( $(date -u +%s) - newest_epoch ) / 60 ))
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
fi

send() {  # send <subject-tail> <body>  -- returns msmtp's exit status
  tag=""; banner=""
  if [ "$TESTMODE" = "1" ]; then
    tag="[TEST]"
    banner="*** FORCED EXERCISE — NOT A REAL OUTAGE. Verify against the published feed before acting. ***

"
  fi
  printf 'From: %s\nTo: %s\nSubject: [1F916]%s %s\n\n%s%s\n' \
    "$FROM" "$TO" "$tag" "$1" "$banner" "$2" | msmtp "$TO"
}

# A send that fails must NOT be recorded as told: leave the state file as it was so
# the next run retries, and write the failure where a human on the box can see it.
# (A mailed alert cannot report that mail is broken; a local file can.)
note_send_failure() {  # note_send_failure <what> <status>
  printf '%s witness-alert: msmtp failed (exit %s) while sending %s; state file left unchanged so the next run retries.\n' \
    "$(date -u +%FT%TZ)" "$2" "$1" >> "$SELFLOG" 2>/dev/null
  printf 'witness-alert: msmtp failed (exit %s) while sending %s\n' "$2" "$1" >&2
}

# A repair is a state change worth a mail even though nothing is now wrong: the
# publisher WAS dark and something moved history. Sent every time a heal runs
# (a heal that keeps recurring is itself the finding). Not gated by $STATE.
if [ -n "${healed:-}" ]; then
  send "${WLABEL} self-healed on ${HOST}" \
"$healed

origin/main $(git rev-parse --short origin/main 2>&1)
newest      ${newest:-unknown}

What happened: something other than this machine pushed to the witness repo, so the
hourly writer's push was being rejected (non-fast-forward). The local commits were
rebased onto origin/main and pushed. Nothing public was rewritten: the rebased
commits had never left this machine. The foreign commit(s) touched nothing under
witness-state/ (checked before the rebase; otherwise this script refuses to heal).

Check the published feed anyway -- a repair is testimony until a reader looks." \
  || note_send_failure "the self-heal notice" "$?"
fi

# --- THE INCIDENT FINGERPRINT (item 5 of the 2026-09-02 review) ------------
# The state file used to mean "already told about AN incident", so a SECOND,
# different problem arriving during an open one -- a dead writer during an
# unpushed-publisher incident -- was never mailed. Once-per-incident is the
# right default; once-per-DISTINCT-incident is what it was supposed to mean.
#
# The fingerprint is the sorted set of problem KINDS, not the problem lines.
# The lines carry ages, commit counts and push-failure totals that move every
# run, so hashing them would turn once-per-incident into once-per-run, which is
# the failure mode this alarm was built to avoid in the other direction. Kinds
# change only when something genuinely new is wrong.
kinds=$(printf '%s' "$problems" | sed -n 's/^\([^:]*\):.*$/\1/p' | sort -u | tr '\n' ',')

prev_since=""
prev_kinds=""
if [ -f "$STATE" ]; then
  prev_since=$(sed -n 's/^since=//p' "$STATE" | head -n 1)
  prev_kinds=$(sed -n 's/^kinds=//p' "$STATE" | head -n 1)
  if [ -z "$prev_since" ]; then
    # Migration from the single-timestamp format written before this change.
    # Adopt the current kinds WITHOUT mailing: a guaranteed false alarm on the
    # run after a deploy would teach the reader to ignore this address, which
    # costs more than the one transition it would catch.
    prev_since=$(head -n 1 "$STATE")
    prev_kinds="$kinds"
    printf 'since=%s\nkinds=%s\n' "$prev_since" "$kinds" > "$STATE"
  fi
fi

if [ -n "$problems" ]; then
  if [ ! -f "$STATE" ]; then
    subject_tail="needs attention"
    changed_note=""
  elif [ "$prev_kinds" != "$kinds" ]; then
    subject_tail="changed"
    changed_note="What changed: this incident opened at ${prev_since} with [${prev_kinds%,}] and now reads [${kinds%,}].
A new kind of problem appeared during an open incident, which is exactly the
case the old once-per-incident rule stayed silent through.

"
  else
    subject_tail=""
    changed_note=""
  fi

  if [ -n "$subject_tail" ]; then
    if [ "$in_repo" = "1" ]; then
      gitstatus=$(git status -b --porcelain 2>&1)
      loglines=$(tail -n 5 witness.log 2>&1)
    else
      gitstatus="(no checkout)"
      loglines="(no checkout)"
    fi
    if send "${WLABEL} ${subject_tail} on ${HOST}" \
"${changed_note}$problems
--- git status ---
$gitstatus

--- last 5 log lines ---
$loglines

Repair for the UNPUSHED/DIVERGED case:
  cd \"$REPO\" && git fetch origin && git rebase origin/main && git push origin main
Rebase, not merge: the log's linearity is a published property of this row.
Nothing public is rewritten — unpushed commits have never left this machine.

This alert is sent once per DISTINCT incident -- again if the set of problem
kinds changes -- and once on recovery."
    then
      # Keep the ORIGINAL opening time across a "changed" mail: the incident did
      # not restart, it grew, and "down since" should say when it began.
      printf 'since=%s\nkinds=%s\n' "${prev_since:-$(date -u +%FT%TZ)}" "$kinds" > "$STATE"
    else
      note_send_failure "the incident alert" "$?"
    fi
  fi
else
  if [ -f "$STATE" ]; then
    if send "${WLABEL} recovered on ${HOST}" \
"Publishing again. Nothing outstanding.

Down since: ${prev_since:-unknown}
Was:        [${prev_kinds%,}]
Now:        $(date -u +%FT%TZ)
origin/main $(git rev-parse --short origin/main 2>&1)
newest      ${newest:-unknown}"
    then
      rm -f "$STATE"
    else
      note_send_failure "the recovery notice" "$?"
    fi
  fi
fi

exit 0
