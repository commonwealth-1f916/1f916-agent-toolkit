#!/bin/sh
# tests/alert.sh -- behaviour tests for witness-alert.sh.
#
# NO SECRET, NO NETWORK, NO REAL MAIL. `msmtp` is a shell script on PATH that
# writes what it was piped into a directory, and the repositories are throwaway
# ones created here. Nothing touches the real witness repo or the real mailbox.
#
# The script under test is Linux-only by its own header (GNU `date -d`, `stat -c`),
# so this suite SKIPS rather than fails where those are absent -- saying so, since
# "skipped" and "passed" are different cells.
#
# Usage: tests/alert.sh [path-to-witness-alert.sh]

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ALERT="${1:-$here/../witness-alert.sh}"
[ -r "$ALERT" ] || { printf 'tests: alert not readable: %s\n' "$ALERT" >&2; exit 1; }

if ! date -u -d "2020-01-01T00:00:00Z" +%s >/dev/null 2>&1 \
   || ! stat -c %Y "$ALERT" >/dev/null 2>&1; then
  printf '# GNU date -d / stat -c not available: SKIPPING the alert suite on this host.\n'
  printf '# witness-alert.sh declares itself Linux-only; this is that, not a pass.\n'
  exit 0
fi

W=$(mktemp -d) || exit 1
trap 'rm -rf "$W"' EXIT
BIN="$W/bin"; MAIL="$W/mail"
mkdir -p "$BIN" "$MAIL"

# --- the fake msmtp -------------------------------------------------------
cat > "$BIN/msmtp" <<'FAKE'
#!/bin/sh
[ -n "${FAKE_MSMTP_FAIL:-}" ] && exit 78
n=$(ls "$FAKE_MSMTP_DIR" | wc -l | tr -d ' ')
cat > "$FAKE_MSMTP_DIR/mail.$n"
exit 0
FAKE
chmod +x "$BIN/msmtp"

pass=0; fail=0; n=0
ok()  { n=$((n+1)); pass=$((pass+1)); printf 'ok %d - %s\n' "$n" "$1"; }
nok() { n=$((n+1)); fail=$((fail+1)); printf 'not ok %d - %s\n' "$n" "$1"
        [ $# -gt 1 ] && printf '  # %s\n' "$2"; }

# The fake msmtp names each mail mail.<n> with n = the count before it, so the
# newest is derivable without asking ls to sort anything.
mails()      { find "$MAIL" -type f | wc -l | tr -d ' '; }
newest_mail(){ c=$(mails); printf 'mail.%s' "$((c-1))"; }
count_is()   { c=$(mails); if [ "$c" = "$2" ]; then ok "$1"; else nok "$1" "expected $2 mail(s), saw $c"; fi; }
body_has()   { m="$MAIL/$(newest_mail)"
               if [ -f "$m" ] && grep -qF -- "$1" "$m"; then ok "$2"
               else nok "$2" "latest mail lacks: $1"; fi; }
body_lacks() { m="$MAIL/$(newest_mail)"
               if [ -f "$m" ] && grep -qF -- "$1" "$m"; then nok "$2" "latest mail contains: $1"
               else ok "$2"; fi; }

# --- a throwaway witness repo --------------------------------------------
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
git init -q --bare "$W/origin.git"
git clone -q "$W/origin.git" "$W/repo" 2>/dev/null
# THE LOCAL BRANCH MUST BE CALLED main, and this line is the whole reason the
# publisher arm of witness-alert.sh had never been tested. A clone of an empty
# bare repo takes git's default init branch, which is `master` on the runners
# and on this container; the script measures `git rev-list --count
# origin/main..main`, which then fails to resolve, so `ahead` and `behind` came
# back "?" and EVERY publisher branch -- the UNPUSHED report, the push-failure
# count, autoheal -- was skipped in silence. Twenty-five tests were green over
# an arm that never ran, and the publisher is the failure this alarm was built
# for: twelve unpushed commits on 2026-09-01. Found 2026-09-20 while writing a
# test for finding 5 that could not be made to fail.
( cd "$W/repo" && git symbolic-ref HEAD refs/heads/main )
mkdir -p "$W/repo/witness-state"

fresh_feed() {  # fresh_feed <minutes-ago>
  ts=$(date -u -d "-$1 minutes" +%Y-%m-%dT%H:%M:%SZ)
  printf '{"at":"%s","status":"countersigned"}\n' "$ts" > "$W/repo/witness-state/countersignatures.jsonl"
}
commit_push() {
  ( cd "$W/repo" && git add -A && git commit -q -m "$1" && git push -q origin HEAD:main 2>/dev/null
    git branch -q --set-upstream-to=origin/main main 2>/dev/null ) || true
}

fresh_feed 5
: > "$W/repo/witness.log"
commit_push "seed"

CONF="$W/conf"
cat > "$CONF" <<CONFEOF
WITNESS_REPO="$W/repo"
WITNESS_ALERT_TO="nobody@example.invalid"
WITNESS_ALERT_FROM="nobody@example.invalid"
WITNESS_ID="6"
WITNESS_ALERT_STATE="$W/state"
WITNESS_ALERT_LOG="$W/selflog"
CONFEOF

# The config is sourced FIRST and overrides the environment -- learned the hard
# way on 2026-09-03, when an exercise with WITNESS_REPO set in the environment
# silently ran against the REAL repository. So every value goes in the file.
run_alert() {
  PATH="$BIN:$PATH" FAKE_MSMTP_DIR="$MAIL" WITNESS_ALERT_CONF="$CONF" \
    bash "$ALERT" > "$W/out" 2> "$W/err"
}

printf '# witness-alert.sh behaviour tests\n# alert: %s\n' "$ALERT"

# 1. Healthy: silence, and no state.
run_alert
count_is "1. a healthy witness sends nothing" 0
if [ ! -f "$W/state" ]; then ok "1. and writes no state file"
else nok "1. and writes no state file" "state exists"; fi

# 2. One problem: one mail, state recorded.
( cd "$W/repo" && fresh_feed 600 && git add -A && git commit -q -m stale && git push -q origin HEAD:main )
run_alert
count_is "2. a stale countersignature alerts once" 1
body_has "STALE:" "2. and names the kind"
if grep -q '^since=' "$W/state" && grep -q '^kinds=' "$W/state"; then ok "2. and records since= and kinds="
else nok "2. and records since= and kinds=" "state is: $(tr '\n' '|' < "$W/state" 2>/dev/null)"; fi
first_since=$(sed -n 's/^since=//p' "$W/state")

# 3. Same problem again: silence. This is the property worth keeping.
run_alert
count_is "3. the same incident does not alert twice" 1

# 4. A SECOND, DIFFERENT problem during the open incident. Before this change
#    the state file's mere existence suppressed this mail entirely.
touch -d "-200 minutes" "$W/repo/witness.log"
run_alert
count_is "4. a NEW kind during an open incident alerts again" 2
body_has "changed" "4. and the mail says what it is"
body_has "NOT RUNNING" "4. and names the new kind"
body_has "STALE" "4. and still names the old one"
body_has "What changed" "4. and shows the before and after"
if [ "$(sed -n 's/^since=//p' "$W/state")" = "$first_since" ]; then ok "4. and keeps the ORIGINAL opening time"
else nok "4. and keeps the ORIGINAL opening time" "since moved"; fi

# 5. Unchanged again: silence.
run_alert
count_is "5. the grown incident does not alert every run" 2

# 6. Recovery.
( cd "$W/repo" && fresh_feed 5 && git add -A && git commit -q -m fixed && git push -q origin HEAD:main )
touch "$W/repo/witness.log"
run_alert
count_is "6. recovery alerts once" 3
body_has "recovered" "6. and says so"
body_has "$first_since" "6. and reports when the incident actually began"
if [ ! -f "$W/state" ]; then ok "6. and clears the state file"
else nok "6. and clears the state file" "state survived"; fi

# 7. A send that fails must NOT be recorded as told.
( cd "$W/repo" && fresh_feed 600 && git add -A && git commit -q -m stale2 && git push -q origin HEAD:main )
PATH="$BIN:$PATH" FAKE_MSMTP_DIR="$MAIL" WITNESS_ALERT_CONF="$CONF" FAKE_MSMTP_FAIL=1 \
  bash "$ALERT" > "$W/out" 2> "$W/err"
count_is "7. a failed send delivers no mail" 3
if [ ! -f "$W/state" ]; then ok "7. and leaves no state, so the next run retries"
else nok "7. and leaves no state, so the next run retries" "state was written anyway"; fi
if [ -s "$W/selflog" ]; then ok "7. and records the failure where a human on the box can see it"
else nok "7. and records the failure where a human on the box can see it" "selflog empty"; fi

# 8. Migration from the pre-fingerprint state format: adopt, do not cry wolf.
rm -f "$W/state"
printf '2026-01-01T00:00:00Z\n' > "$W/state"
run_alert
count_is "8. an old-format state file does not produce a false alarm" 3
if grep -q '^kinds=' "$W/state"; then ok "8. and is upgraded in place"
else nok "8. and is upgraded in place" "state is: $(tr '\n' '|' < "$W/state")"; fi
if [ "$(sed -n 's/^since=//p' "$W/state")" = "2026-01-01T00:00:00Z" ]; then ok "8. keeping the original opening time"
else nok "8. keeping the original opening time" "since was rewritten"; fi

# 9. And from there a genuinely new kind still alerts.
touch -d "-200 minutes" "$W/repo/witness.log"
run_alert
count_is "9. after migration a new kind still alerts" 4
body_lacks "nobody@example.invalid: command not found" "9. and the fake msmtp really ran"

# --- the 2026-09-20 review, finding 5 -------------------------------------
# Three small defects, none of which any test reached: the suite had never
# produced an UNPUSHED problem and had never made a fetch fail.

# 10. `grep -c` PRINTS 0 and EXITS 1 on a readable file with no match, so the
#     old `|| echo 0` appended a SECOND zero and the mail read "records 0\n0
#     'push failed' line(s)". The assertion is the whole string on one line,
#     which is exactly what the old form could not produce.
rm -f "$W/state"
( cd "$W/repo" && fresh_feed 5 && touch witness.log && git add -A && git commit -q -m "local only" )
run_alert
count_is "10. an unpushed commit alerts" 5
body_has "UNPUSHED:" "10. and names the kind"
body_has "records 0 'push failed' line(s)" "10. and the push-failure total renders as ONE number"

# 11. ...and a log it cannot read is UNKNOWN, not zero. The old form collapsed
#     "no failures logged" and "no log to read" into the same 0.
rm -f "$W/state" "$W/repo/witness.log"
run_alert
count_is "11. a missing witness.log alerts" 6
body_has "UNKNOWN -- not zero" "11. and the push-failure total is unknown rather than zero"

# 12. A FAILING FETCH. git's errors are multi-line, and the fingerprint takes
#     each problem line's leading "word:" as a KIND -- so a second line
#     beginning "fatal:" used to invent a kind called `fatal`, out of text that
#     varies run to run, which is how a fingerprint flaps. The state file is
#     where the fingerprint is written down, so that is where this is checked.
rm -f "$W/state"
: > "$W/repo/witness.log"
( cd "$W/repo" && git remote set-url origin "$W/there-is-no-repo-here.git" )
PATH="$BIN:$PATH" FAKE_MSMTP_DIR="$MAIL" WITNESS_ALERT_CONF="$CONF" WITNESS_AUTOHEAL=1 \
  bash "$ALERT" > "$W/out" 2> "$W/err"
count_is "12. an unreachable origin alerts" 7
body_has "FETCH FAILED:" "12. and names the kind"
if [ -f "$W/state" ] && ! grep -q 'fatal' "$W/state"; then
  ok "12. and git's second error line did not become a problem KIND"
else nok "12. and git's second error line did not become a problem KIND" \
        "kinds are: $(sed -n 's/^kinds=//p' "$W/state" 2>/dev/null)"; fi
if [ -f "$W/state" ] && [ "$(sed -n 's/^kinds=//p' "$W/state" | tr ',' '\n' | grep -c .)" -le 3 ]; then
  ok "12. and the fingerprint is a short set of kinds, not a line of error text"
else nok "12. and the fingerprint is a short set of kinds, not a line of error text" \
        "kinds are: $(sed -n 's/^kinds=//p' "$W/state" 2>/dev/null)"; fi
body_has "AUTOHEAL SKIPPED:" "12. and autoheal did not rebase onto a stale origin/main"

( cd "$W/repo" && git remote set-url origin "$W/origin.git" )

printf '# %d tests, %d passed, %d failed\n' "$n" "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
