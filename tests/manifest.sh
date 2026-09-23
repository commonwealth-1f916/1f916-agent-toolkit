#!/bin/sh
# tests/manifest.sh -- docs/MANIFEST names every published doc with its sha-256,
# and the tree agrees with it.
#
# Why a manifest at all. The scheduled runs read these documents in order to
# act, and the plan of record is that they fetch them at the commit their
# prompt already pins for the four programs. A prompt then carries one digest
# for the tools and nothing per doc, because `1f916-checks manifest --base
# <raw url at the pin>/docs --manifest <the MANIFEST fetched the same way>`
# verifies every doc against the manifest, and the manifest against the
# commit. That only holds if the manifest is TRUE, which is what this test
# enforces on every push: a doc edited without its manifest line, or a doc
# added and not named, fails here rather than at run time.
#
# One recipe, not two: the manifest is rendered from the `computed` list the
# subcommand itself returns, so the file and the check cannot drift apart.
#
# No secret, no network.
#
#   sh tests/manifest.sh              docs/MANIFEST agrees with docs/
#   sh tests/manifest.sh --update     rewrite docs/MANIFEST from the tree
#   sh tests/manifest.sh --self-test  plant a changed, a missing and an extra
#                                     doc in a copy and REQUIRE each to be
#                                     reported; then require the real tree to
#                                     pass

set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
CHECKS="$root/1f916-checks"
DOCS="$root/docs"
MANIFEST="$DOCS/MANIFEST"

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

command -v python3 >/dev/null 2>&1 || { echo "not ok - python3 not found on PATH"; exit 1; }

render() {  # render <dir> <manifest> -> the manifest the tree would produce, on stdout
  python3 "$CHECKS" manifest --manifest "$2" --dir "$1" | python3 -c '
import json, sys
out = json.load(sys.stdin)
if out["status"] != "ok":
    sys.stderr.write("manifest check could not run: %s\n" % out["reason"])
    sys.exit(3)
for c in out["computed"]:
    sys.stdout.write("%s  %s\n" % (c["sha256"], c["path"]))
'
}

verdict() {  # verdict <dir> <manifest> -> "ok" or the named lists
  python3 "$CHECKS" manifest --manifest "$2" --dir "$1" | python3 -c '
import json, sys
out = json.load(sys.stdin)
if out["status"] != "ok":
    print("could_not_run: " + str(out["reason"])); sys.exit(0)
if out["all_match"]:
    print("ok"); sys.exit(0)
print("mismatched=%s missing=%s extra=%s" % (
    [m["path"] for m in out["mismatched"]], out["missing"], out["extra"]))
'
}

n=0; failed=0
ok()     { n=$((n + 1)); echo "ok $n - $1"; }
not_ok() { n=$((n + 1)); failed=1; echo "not ok $n - $1"; }

case "${1:-}" in
  --update)
    # The subcommand refuses a manifest with no entries, so a first run seeds
    # one from a throwaway line: the digest is wrong on purpose and `computed`
    # is what gets rendered, not the seed.
    seed=$(mktemp) || exit 1
    if [ -s "$MANIFEST" ]; then cp "$MANIFEST" "$seed"; else
      first=""
      for f in "$DOCS"/*.md; do first="$f"; break; done
      printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$(basename "$first")" > "$seed"
    fi
    tmp=$(mktemp) || exit 1
    render "$DOCS" "$seed" > "$tmp" || { rm -f "$tmp" "$seed"; exit 1; }
    rm -f "$seed"
    mv "$tmp" "$MANIFEST"
    echo "docs/MANIFEST rewritten: $(grep -c . "$MANIFEST") entries"
    exit 0 ;;
  --self-test)
    WORK=$(mktemp -d) || exit 1
    trap 'rm -rf "$WORK"' EXIT
    cp -R "$DOCS" "$WORK/docs"
    # The copy passes first, or the plants below prove nothing.
    v=$(verdict "$WORK/docs" "$WORK/docs/MANIFEST")
    if [ "$v" = "ok" ]; then ok "the copy of docs/ passes before anything is planted"; else not_ok "the copy fails before any plant: $v"; fi
    printf '\n<!-- planted -->\n' >> "$WORK/docs/brief.md"
    v=$(verdict "$WORK/docs" "$WORK/docs/MANIFEST")
    case "$v" in *"mismatched=['brief.md']"*) ok "a changed doc is reported as mismatched" ;; *) not_ok "a changed doc was not reported: $v" ;; esac
    cp "$DOCS/brief.md" "$WORK/docs/brief.md"
    rm "$WORK/docs/witness.md"
    v=$(verdict "$WORK/docs" "$WORK/docs/MANIFEST")
    case "$v" in *"missing=['witness.md']"*) ok "a doc the manifest names but the tree lacks is reported as missing" ;; *) not_ok "a missing doc was not reported: $v" ;; esac
    cp "$DOCS/witness.md" "$WORK/docs/witness.md"
    printf 'unmanifested\n' > "$WORK/docs/zz-planted.md"
    v=$(verdict "$WORK/docs" "$WORK/docs/MANIFEST")
    case "$v" in *"extra=['zz-planted.md']"*) ok "a doc the tree holds and the manifest does not name is reported as extra" ;; *) not_ok "an extra doc was not reported: $v" ;; esac
    rm "$WORK/docs/zz-planted.md"
    : > "$WORK/docs/MANIFEST"
    v=$(verdict "$WORK/docs" "$WORK/docs/MANIFEST")
    case "$v" in could_not_run:*"no entries"*) ok "an empty manifest is could-not-run, never a pass" ;; *) not_ok "an empty manifest did not refuse: $v" ;; esac
    ;;
esac

[ -f "$MANIFEST" ] || { not_ok "docs/MANIFEST does not exist (sh tests/manifest.sh --update writes it)"; echo "FAILED"; exit 1; }
v=$(verdict "$DOCS" "$MANIFEST")
if [ "$v" = "ok" ]; then ok "docs/MANIFEST names every doc under docs/ with its current sha-256"; else not_ok "docs/MANIFEST disagrees with the tree ($v); run sh tests/manifest.sh --update and commit both"; fi
tmp=$(mktemp) || exit 1
render "$DOCS" "$MANIFEST" > "$tmp"
if cmp -s "$tmp" "$MANIFEST"; then ok "docs/MANIFEST is byte-identical to what the tree renders (order, format, trailing newline)"; else not_ok "docs/MANIFEST differs from the rendered form; run sh tests/manifest.sh --update"; fi
rm -f "$tmp"

if [ "$failed" = 0 ]; then echo "PASSED"; exit 0; fi
echo "FAILED"; exit 1
