#!/bin/sh
# tests/mutants.sh -- does the suite in tests/gate.sh actually go red?
#
# A green check earns nothing until it has been shown capable of going red on
# the exact input it is meant to catch. This project has filed that finding
# against other people's instruments repeatedly; running it against our own is
# the cheap part. Each mutant below is a one-line edit to a COPY of the gate
# that breaks a property the suite claims to cover. Every mutant must make
# tests/gate.sh fail. A mutant that survives is a hole in the suite.
#
# No secret, no network. Usage: tests/mutants.sh

# The sed expressions in this file must reach sed unexpanded; that is the point.
# shellcheck disable=SC2016

set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
GATE="$here/../1f916-gate"
ALERT="$here/../witness-alert.sh"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

killed=0; survived=0

mutant() {  # mutant <name> <sed-expression> [gate|alert]
  case "${3:-gate}" in
    alert) src="$ALERT"; suite="$here/alert.sh" ;;
    *)     src="$GATE";  suite="$here/gate.sh"  ;;
  esac
  cp "$src" "$WORK/subject"
  sed -i.bak "$2" "$WORK/subject" 2>/dev/null || sed -i "$2" "$WORK/subject"
  if cmp -s "$src" "$WORK/subject"; then
    printf 'ERROR  %-52s the edit changed nothing -- fix the mutant\n' "$1"
    survived=$((survived+1)); return
  fi
  if sh "$suite" "$WORK/subject" >/dev/null 2>&1; then
    printf 'SURVIVED %-50s the suite did not notice\n' "$1"
    survived=$((survived+1))
  else
    printf 'killed   %-50s\n' "$1"
    killed=$((killed+1))
  fi
}

printf '# mutation check on tests/gate.sh\n'

mutant 'allowlist loses /api/model'          's|/api/porch/knock\|/api/withdraw\|/api/model)|/api/porch/knock\|/api/withdraw)|'
mutant 'allowlist admits everything'         's|^       \*) fail3 "path not on the write allowlist: \$2" ;;|       *) ;;|'
mutant 'hash mismatch stops failing'         's|^  exit 2$|  exit 0|'
mutant 'BEARER is no longer required'        's|^\[ -n "\${BEARER:-}" \].*$||'
mutant 'key mismatch falls through'          's|^      fail5 "KEY MISMATCH|      : "KEY MISMATCH|'
mutant 'key-check sends after all'           's|^      exit 0$|      :|'
mutant 'a bad status becomes success'        's|^  \*)  fail4 "registry answered|  *)  printf "registry answered|'
mutant 'unreadable seals is not fatal'       's|fail3 "could not fetch seals endpoint -- gate did not run"|true|'

# The 2026-09-02 review's remaining items, each mutated back out again.
mutant 'body JSON validation removed'        's|^     jq -e \. "\$3" >/dev/null 2>&1 .*$||'
mutant 'digest-tool check removed'           's|^\[ -n "\$SHA256" \].*$||'
mutant 'scheme pinning removed'              "s|--proto '=https' ||g"
mutant 'handle encoding removed'             's|citizen=\$handle_enc|citizen=$HANDLE|'
mutant 'response scan removed'               's|^if \[ -s "\$tmp" \] && SECRET=.*$|if false; then|'
mutant 'empty-status check removed'          's|^\[ -n "\$status" \] .. fail4 .*$||'
mutant 'bearer put back on curl argv'      's|-K - |-K - -H "Authorization: Bearer $BEARER" |g'
mutant 'config never read by curl'         's|-K - ||g'

# --- witness-alert.sh -----------------------------------------------------
# Skipped where the alert suite skips: the script is Linux-only by its header,
# and a mutant that "survives" because the suite never ran would be a lie.
if date -u -d "2020-01-01T00:00:00Z" +%s >/dev/null 2>&1 && stat -c %Y "$ALERT" >/dev/null 2>&1; then
  mutant 'incident fingerprint frozen'      's|^kinds=\$(printf .*$|kinds="always-the-same"|'      alert
  mutant 'state written despite a failed send' 's|^      note_send_failure "the incident alert" "\$?"|      printf "since=x\\nkinds=y\\n" > "$STATE"|' alert
  mutant 'recovery never clears the state'  's|^      rm -f "\$STATE"$|      :|'                    alert
  mutant 'migration cries wolf'             's|^    prev_kinds="\$kinds"$|    prev_kinds="ZZZ"|'    alert
else
  printf '# GNU date -d / stat -c absent: alert mutants skipped, not passed\n'
fi

printf '# %d killed, %d survived\n' "$killed" "$survived"
[ "$survived" = 0 ] || exit 1
