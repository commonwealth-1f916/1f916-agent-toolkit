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
RUNTOOL="$here/../1f916-run"
SCANTOOL="$here/../1f916-scan"
SIGNTOOL="$here/../1f916-ssh-sign"
SEEDTOOL="$here/../1f916-seed-to-sshkey.mjs"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

killed=0; survived=0

mutant() {  # mutant <name> <sed-expression> [gate|run|scan|sign|seed|alert]
  name="$1"; expr="$2"; kind="${3:-gate}"
  second=""
  case "$kind" in
    alert) src="$ALERT"; suite="$here/alert.sh" ;;
    run)   src="$RUNTOOL"; suite="$here/run.sh" ;;
    scan)  src="$SCANTOOL"; suite="$here/scan.sh" ;;
    sign)  src="$SIGNTOOL"; suite="$here/sign.sh" ;;
    seed)  src="$SEEDTOOL"; suite="$here/sign.sh"; second="$SIGNTOOL" ;;
    *)     src="$GATE";  suite="$here/gate.sh"  ;;
  esac
  cp "$src" "$WORK/subject"
  chmod +x "$WORK/subject"
  sed -i.bak "$expr" "$WORK/subject" 2>/dev/null || sed -i "$expr" "$WORK/subject"
  if cmp -s "$src" "$WORK/subject"; then
    printf 'ERROR  %-52s the edit changed nothing -- fix the mutant\n' "$name"
    survived=$((survived+1)); return
  fi
  # tests/sign.sh takes TWO subjects, and which one is mutated decides the
  # argument order: `sign` mutates the wrapper and the real seed tool goes
  # second; `seed` mutates the seed tool and the real wrapper goes first.
  case "$kind" in
    sign) set -- "$WORK/subject" "$SEEDTOOL" ;;
    seed) set -- "$second" "$WORK/subject" ;;
    *)    set -- "$WORK/subject" ;;
  esac
  if sh "$suite" "$@" >/dev/null 2>&1; then
    printf 'SURVIVED %-50s the suite did not notice\n' "$name"
    survived=$((survived+1))
  else
    printf 'killed   %-50s\n' "$name"
    killed=$((killed+1))
  fi
}

printf '# mutation check on tests/gate.sh\n'

mutant 'allowlist loses /api/model'          's|/api/withdraw\|/api/model\|/api/attestations\|/api/me/cadence)|/api/withdraw\|/api/attestations\|/api/me/cadence)|'
mutant 'allowlist loses /api/attestations'   's|/api/model\|/api/attestations\|/api/me/cadence)|/api/model\|/api/me/cadence)|'
mutant 'allowlist loses /api/me/cadence'     's|/api/attestations\|/api/me/cadence)|/api/attestations)|'
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

# --- 1f916-run --------------------------------------------------------------
# The wrapper's own properties: the shape check on the gate file, the stop at
# the first failed step, and the loading of each field. tests/run.sh runs the
# REAL gate behind the mutated wrapper, so a survivor here is a hole in that
# suite and not in the gate's.
mutant 'header check removed'              's|^\[ "\$first" = "1f916 continuity core v1" \] .*$||'                 run
mutant 'unexpected lines accepted'         's|^    \*) fail3 "gate file has an unexpected line.*$|    *) ;;|'       run
mutant 'a failed step no longer stops'     's|^    exit "\$rc"$|    :|'                                            run
mutant 'secret line no longer loaded'      's|^    secret=\*)       BEARER=\${line#secret=} ;;$|    secret=*) ;;|' run
mutant 'empty manifest reported done'       's|^      .. fail3 "manifest is not a non-empty JSON array: \$manifest"$|      \|\| true|' run

# --- 1f916-scan ------------------------------------------------------------
# Until 2026-09-14 this tool had no mutants at all, while tests/scan.sh ran on
# every push. That is the shape this file exists to refuse: the scanner's green
# summary line is the ONLY evidence that a bearer is not still on disk -- every
# run records it, and the brief's rule 2 says never to trust a sentence saying
# a secret was deleted. A scanner broken into always-passing prints exactly the
# line a clean tree prints. On 2026-09-02 the scan was itself the leak; this is
# the cheaper half of not repeating that.
mutant 'the verdict is always clean'      's|^\[ "\$matched" -eq 0 \]$|true|'                            scan
mutant 'the pattern file counts as a hit' 's# | grep -Fxv -- "\$patabs"##'                               scan
mutant 'patterns become regexes'          's|grep -rlaF -f|grep -rla -f|'                                scan
mutant 'an empty pattern file is answered' 's|^if ! grep -q .\[^\[:space:\]\]. "\$pat"; then$|if false; then|' scan
mutant 'a missing path is not counted'    's|^    unreadable=\$((unreadable+1)); continue$|    continue|' scan
# The last one needs a path that EXISTS and cannot be read, which root does not
# have. Skipped and said so under root rather than reported as a survivor -- a
# mutant that "survives" because its test never ran is the same lie the alert
# block below refuses. CI runs unprivileged on both runners.
if [ "$(id -u)" != "0" ]; then
  mutant 'stderr no longer counts as unreadable' 's|^  unreadable=\$((unreadable + \$(wc -l <"\$tmp_err")))$|  :|' scan
else
  printf '# running as root: the unreadable-path mutant was SKIPPED, not passed\n'
fi

# --- witness-alert.sh -----------------------------------------------------
# Skipped where the alert suite skips: the script is Linux-only by its header,
# and a mutant that "survives" because the suite never ran would be a lie.
if date -u -d "2020-01-01T00:00:00Z" +%s >/dev/null 2>&1 && stat -c %Y "$ALERT" >/dev/null 2>&1; then
  mutant 'incident fingerprint frozen'      's|^kinds=\$(printf .*$|kinds="always-the-same"|'      alert
  mutant 'state written despite a failed send' 's|^      note_send_failure "the incident alert" "\$?"|      printf "since=x\\nkinds=y\\n" > "$STATE"|' alert
  mutant 'recovery never clears the state'  's|^      rm -f "\$STATE"$|      :|'                    alert
  mutant 'migration cries wolf'             's|^    prev_kinds="\$kinds"$|    prev_kinds="ZZZ"|'    alert
  # The 2026-09-20 review's finding 5, and the publisher arm generally. Until
  # that day the alert suite's throwaway clone was on `master`, so `ahead` and
  # `behind` resolved to "?" and every mutant below would have survived by
  # never being reached.
  mutant 'unpushed commits are not reported' 's|UNPUSHED: local main is|FINE: local main is|'      alert
  mutant 'the push-failure count doubles'    's|^      pushfails=\$(grep -c .*$|      pushfails=$(grep -c "push failed" witness.log 2>/dev/null \|\| echo 0)|' alert
  mutant 'an unreadable log counts as zero'  's|^      problems="\${problems}. witness.log is not readable.*$|      problems="${problems}. witness.log records 0 (log) line(s).\n"|' alert
  mutant 'a multi-line fetch error is raw'   's|^    fetch_err=\$(printf .*tr .*)$|    :|'         alert
  mutant 'autoheal runs on a stale ref'      's|^  if \[ "\$fetch_ok" = "0" \] && \[ "\$AUTOHEAL" = "1" \]; then$|  if false; then|' alert
else
  printf '# GNU date -d / stat -c absent: alert mutants skipped, not passed\n'
fi

# --- the signing chain ------------------------------------------------------
# No mutants existed for either of these until 2026-09-20, because tests/sign.sh
# could only run against the files beside it and tests/mutants.sh runs a suite
# against a mutated COPY. Both are the 2026-09-20 review's items 6 and 7.
if command -v ssh-keygen >/dev/null 2>&1 && command -v ssh-agent >/dev/null 2>&1; then
  mutant 'the agent key has no lifetime'   's|ssh-add -q -t 30 -|ssh-add -q -|'                    sign
  mutant 'the key command stderr is lost'  's|ssh-add -q -t 30 -|ssh-add -q -t 30 - 2>/dev/null|'  sign
  mutant 'HANDLE is not required by the wrapper' 's|^  \[ -n "\${HANDLE:-}" \].*$||'                sign
  mutant 'HANDLE is defaulted again'       's|^const HANDLE = process.env.HANDLE;$|const HANDLE = process.env.HANDLE \|\| "commonwealth";|' seed
else
  printf '# no ssh-keygen/ssh-agent: signing mutants skipped, not passed\n'
fi

printf '# %d killed, %d survived\n' "$killed" "$survived"
[ "$survived" = 0 ] || exit 1
