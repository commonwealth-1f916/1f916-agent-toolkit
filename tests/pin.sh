#!/bin/sh
# tests/pin.sh -- does this change touch code the scheduled runs execute?
#
# Three files in this repository are fetched at a PINNED COMMIT by the two
# scheduled runs and executed with the citizen's bearer token in play. Changing
# one of them on main does not change what the runs do: they keep fetching the
# pinned commit and checking its digests, so a merged improvement sits unused
# until a person moves the pin in three places and cuts a signed tag.
#
# That gap is the pin doing its job -- the thing that runs the toolchain cannot
# edit the toolchain -- but twice in September it ran silently for weeks. The
# allowlist gained /api/attestations on the 7th and was unreachable until the
# 14th; a second pin in the operator's brief sat 36 commits behind and was found
# by accident. The weekly audit now reconciles both, but weekly is the cadence,
# and the person who could act was at the keyboard on merge day.
#
# So this fires where that person already is. It is a REMINDER AND NOT A
# CONTROL, and the distinction is the whole reason to say it here: this file
# lives in the repository it guards, so a pull request that edits it turns it
# off, and a direct push to main never runs it at all (one has happened --
# 535cf76). The control is the pinned digest in the stored prompts, which no
# scheduled run can write. This only makes forgetting hard.
#
# Usage:
#   sh tests/pin.sh <base-ref> <head-ref>   names the tool files that changed
#   sh tests/pin.sh --digests [<ref>]       the three digests, for pasting
#   sh tests/pin.sh --self-test             proves this script can go red
#
# Exit 0: no tool file changed.  Exit 1: at least one did, and the pin is owed.

set -e

TOOLS='1f916-gate 1f916-run 1f916-scan'

# macOS ships shasum, Debian ships sha256sum, and this script guards a program
# that runs on both. Same reason tests/gate.sh carries the pair.
digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

print_digests() {
  _ref="${1:-HEAD}"
  for _t in $TOOLS; do
    _tmp=$(mktemp)
    git show "$_ref:$_t" > "$_tmp"
    echo "  $_t  $(digest "$_tmp")"
    rm -f "$_tmp"
  done
}

changed_tools() {
  # Three dots: what this branch changed, not what main changed underneath it.
  #
  # $TOOLS is unquoted on purpose: it is three pathspecs, not one. Quoting it
  # would ask git for a single path named "1f916-gate 1f916-run 1f916-scan",
  # which matches nothing -- and a check that silently matches nothing is the
  # failure mode this whole file exists to refuse.
  # shellcheck disable=SC2086
  git diff --name-only "$1...$2" -- $TOOLS
}

self_test() {
  _work=$(mktemp -d)
  trap 'rm -rf "$_work"' EXIT
  (
    cd "$_work"
    git init -q .
    git config user.email t@example.invalid
    git config user.name t
    for t in $TOOLS; do echo "#!/bin/sh" > "$t"; done
    echo readme > README.md
    git add -A && git commit -qm base
    git branch -q base

    # (1) a change that touches no tool file must pass
    echo "more" >> README.md
    git commit -qam docs
    if changed_tools base HEAD | grep -q .; then
      echo "self-test FAILED: a docs-only change was reported as a tool change" >&2
      exit 1
    fi

    # (2) a change that touches one must be caught -- the case that matters,
    #     run second so a broken detector cannot pass by never firing.
    echo "# edit" >> 1f916-gate
    git commit -qam gate
    if ! changed_tools base HEAD | grep -q '^1f916-gate$'; then
      echo "self-test FAILED: an edit to 1f916-gate was NOT caught" >&2
      exit 1
    fi

    # (3) and a rename away from the guarded name must be caught too
    git mv 1f916-scan 1f916-scan-old
    git commit -qm rename
    if ! changed_tools base HEAD | grep -q '^1f916-scan$'; then
      echo "self-test FAILED: removing 1f916-scan was NOT caught" >&2
      exit 1
    fi
  )
  echo "self-test passed: the check fires on a tool change and stays quiet otherwise"
}

case "${1:-}" in
  --self-test) self_test; exit 0 ;;
  --digests)   print_digests "${2:-HEAD}"; exit 0 ;;
  '')          echo "usage: sh tests/pin.sh <base-ref> <head-ref> | --digests [ref] | --self-test" >&2; exit 2 ;;
esac

[ -n "${2:-}" ] || { echo "usage: sh tests/pin.sh <base-ref> <head-ref>" >&2; exit 2; }

hits=$(changed_tools "$1" "$2")

if [ -z "$hits" ]; then
  echo "No tool file changed. The pin is unaffected and nothing is owed."
  exit 0
fi

echo "THIS CHANGE TOUCHES CODE THE SCHEDULED RUNS EXECUTE:"
echo "$hits" | sed 's/^/  /'
echo
echo "Digests at $2:"
print_digests "$2"
echo
cat <<'OWED'
Merging this does NOT deploy it. The runs fetch a pinned commit and verify
three digests before executing anything, so until the pin moves they keep
running the old code and nothing reports the gap for up to a week.

What is owed, and it is one sitting:
  1. move the pin + digests in the 12:00 prompt, step 1
  2. move the pin + digests in the 23:00 prompt, step 1
  3. move the pin + the 1f916-scan digest in the brief, security rule 2
  4. cut a SIGNED, ANNOTATED tag on the merge commit and push it
  5. update the ledger row prompts/toolkit-pin

Cut the tag when the pin moves, not when this merges: then every tag names
code that actually ran, and "the pin resolves to a signed tag" stays a thing
the weekly audit can check.

Deliberately not deploying yet? Label this pull request `pin-deferred` and say
why in the body. The label is the acknowledgement, not a way around the check.
OWED
exit 1
