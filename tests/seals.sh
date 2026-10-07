#!/bin/sh
# tests/seals.sh -- run tests/seals.mjs against seals/ledger-genesis.mjs, or
# against the copy named in $1 (tests/mutants.sh passes a mutated one).
#
# The tool imports @noble/curves for the BLS check, pinned by
# seals/package-lock.json. Install it first, from the lockfile only:
#   npm ci --prefix seals --ignore-scripts
# Missing dependencies are exit 3 -- the suite could not run -- never a pass.
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
mods="$here/../seals/node_modules"
[ -d "$mods/@noble/curves" ] || { echo "seals/node_modules is missing: npm ci --prefix seals --ignore-scripts"; exit 3; }
command -v node >/dev/null 2>&1 || { echo "node not found"; exit 3; }
subject="${1:-$here/../seals/ledger-genesis.mjs}"
d=$(dirname -- "$subject")
case "$subject" in
  *.mjs) ;;
  *) cp "$subject" "$d/subject.mjs"; subject="$d/subject.mjs" ;;
esac
# An ES module resolves its imports from its own folder upwards, so a copy
# outside seals/ is given a link to the pinned modules beside it.
[ -e "$d/node_modules" ] || ln -s "$mods" "$d/node_modules"
exec node "$here/seals.mjs" "$subject"
