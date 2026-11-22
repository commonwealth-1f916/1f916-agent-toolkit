#!/bin/sh
# .github/pin-close-owed.sh BEFORE AFTER -- close the "toolkit pin owed" issues
# a pin move has discharged. Run by pin.yml's record job on every push to main.
#
# The issue a merge opens asks for one thing: a signed pin naming that commit
# (or a later one) on main, with its signed tag. When a push changes pin/PIN,
# this checks that the new PIN verifies against the identity key the registry
# serves, that its serial went up, and that its tag is signed by the same key
# and names the pinned commit. Only then does it close each open owed issue
# whose commit the pinned commit contains, with a comment naming serial, tag
# and commit. Anything it cannot verify closes nothing and says why: a bad or
# unchecked pin must never hide owed work. The ledger row prompts/toolkit-pin
# is still the sitting's to update; the weekly audit reads it.
#
# Environment: GH_TOKEN (issues: write). For a sitting's dry run:
#   DRY_RUN=1          print what would be closed, close nothing
#   KEY_JSON=FILE      the registry key document instead of fetching it
#   ISSUES_JSON=FILE   [{"number":N,"title":"..."}] instead of listing issues
set -eu
BEFORE=$1 AFTER=$2
FP='SHA256:q2yRbCWjFFYblk+Fb2yBiKBpl+PLM1SnhJX/veRUsOs'
KEYS_URL='https://1f916.ai/api/keys/commonwealth'
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
say() { printf '%s\n' "$*"; }

if git diff --quiet "$BEFORE" "$AFTER" -- pin/PIN pin/PIN.sig; then
  say "pin/PIN unchanged by this push: nothing to close."
  exit 0
fi
git show "$AFTER:pin/PIN" > "$t/PIN"
git show "$AFTER:pin/PIN.sig" > "$t/PIN.sig"
git show "$AFTER:1f916-pin" > "$t/1f916-pin"
old=0
if git cat-file -e "$BEFORE:pin/PIN" 2>/dev/null; then
  old=$(git show "$BEFORE:pin/PIN" | sed -n 's/^serial \([0-9][0-9]*\)$/\1/p')
fi
if [ -n "${KEY_JSON:-}" ]; then cp "$KEY_JSON" "$t/key.json"
elif ! curl -fsS -m 30 -o "$t/key.json" "$KEYS_URL"; then
  say "::warning::could not fetch the registry key: no issue closed (could not run)"
  exit 0
fi
if ! python3 "$t/1f916-pin" verify --pin "$t/PIN" --sig "$t/PIN.sig" \
     --key-json "$t/key.json" --fingerprint "$FP" --min-serial $((old + 1)) > "$t/v.json"; then
  say "::warning::pin/PIN did not verify (or its serial did not rise above $old): no issue closed"
  cat "$t/v.json"
  exit 0
fi
serial=$(sed -n 's/^serial //p' "$t/PIN")
commit=$(sed -n 's/^commit //p' "$t/PIN")
tag=$(sed -n 's/^tag //p' "$t/PIN")
if ! git cat-file tag "$tag" > "$t/tag.obj" 2>/dev/null; then
  say "::warning::tag $tag is not an annotated tag in this clone: no issue closed"
  exit 0
fi
if ! python3 "$t/1f916-pin" tag-verify --tag-object "$t/tag.obj" --key-json "$t/key.json" \
     --fingerprint "$FP" --expect-object "$commit" --expect-tag "$tag" > "$t/tv.json"; then
  say "::warning::tag $tag did not verify against the identity key for $commit: no issue closed"
  cat "$t/tv.json"
  exit 0
fi
say "pin verified: serial $serial (was $old), commit $commit, signed tag $tag"

if [ -n "${ISSUES_JSON:-}" ]; then cp "$ISSUES_JSON" "$t/issues.json"
else
  gh issue list --state open --search '"toolkit pin owed" in:title' --limit 100 \
    --json number,title > "$t/issues.json"
fi
python3 -c 'import json,sys
for i in json.load(open(sys.argv[1])):
    t = i["title"]
    if t.startswith("toolkit pin owed: "):
        print(i["number"], t.split(": ", 1)[1])' "$t/issues.json" > "$t/owed.txt"
closed=0
while read -r num prefix; do
  case $prefix in *[!0-9a-f]*|'') say "#$num: '$prefix' is not a commit prefix, left open"; continue;; esac
  if ! c=$(git rev-parse --verify --quiet "$prefix^{commit}"); then
    say "#$num: $prefix does not resolve in this clone, left open"; continue
  fi
  if ! git merge-base --is-ancestor "$c" "$commit"; then
    say "#$num: $prefix is not contained in the pinned commit, left open"; continue
  fi
  body="Discharged by pin serial $serial (signed \`pin/PIN\` on main at ${AFTER}), which names commit \`$commit\` with signed tag \`$tag\`; both verified against the identity key ($FP) the registry serves, and \`$prefix\` is contained in the pinned commit. Closed by pin.yml. The ledger row \`prompts/toolkit-pin\` is updated by the sitting that moved the pin."
  if [ "${DRY_RUN:-}" = 1 ]; then
    say "#$num: would close ($prefix in $commit)"
  else
    gh issue close "$num" --comment "$body"
    say "#$num: closed"
  fi
  closed=$((closed + 1))
done < "$t/owed.txt"
say "$closed owed issue(s) closed"
