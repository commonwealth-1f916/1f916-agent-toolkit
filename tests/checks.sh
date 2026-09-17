#!/bin/sh
# tests/checks.sh -- acceptance tests for 1f916-checks.
#
# NO SECRET AND NO NETWORK. Every fetch the tests make is answered from
# tests/fixtures/checks/ through --offline-dir, and every git remote is a
# throwaway repository in a temp directory reached by a file:// URL. The tests
# themselves are Python (tests/test_checks.py), because the program is; this
# wrapper exists so CI and a person run them the same way as every other suite.
#
# The fixtures, and what was done to them:
#   surface.json              GET /api/surface as served on 2026-09-17, whole.
#                             It reproduces the route and capability digests the
#                             ledger stored on 2026-09-16, and the test holds those
#                             two values as literals.
#   witness-head.jsonl        the first 300 lines of the public witness file,
#                             TRUNCATED from 1,240 lines (703 KB) to stay under
#                             200 KB. Nothing else changed; the tests that need a
#                             modified line or a refused line build it in a temp dir.
#   record.json, front.json,  live payloads cut down to the fields the checks
#   new.json, seals-*.json    read. Post titles, bodies and authors are removed
#                             from front.json -- they are citizen-authored text and
#                             no test reads them.
#   homepage.html             synthetic. Only its bytes are hashed.
#   prior-*.json              ledger rows stripped to the fields the checks
#                             compare. Free-text fields are not carried.
#
# A green run here is only worth something because the suite has been shown
# failing: test_checks.RedPath breaks the canonical serialisation three ways
# and requires the golden digests to reject each one.
#
# Usage: sh tests/checks.sh

set -u

# The suite imports the script as a module; keep the bytecode out of the tree.
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if ! command -v python3 >/dev/null 2>&1; then
  # Not a skip: 1f916-checks is a Python program, and a host with no python3
  # cannot run what these tests describe.
  echo "not ok - python3 not found on PATH"
  exit 1
fi

python3 -m py_compile "$here/../1f916-checks" 2>&1 || { echo "not ok - 1f916-checks does not compile"; exit 1; }
# py_compile leaves a cache directory beside the script; it is not ours to leave.
rm -rf "$here/../__pycache__"

cd "$here/.." || exit 1
if python3 -m unittest discover -s tests -p 'test_checks*.py' -v; then
  echo "PASSED"
  exit 0
fi
echo "FAILED"
exit 1
