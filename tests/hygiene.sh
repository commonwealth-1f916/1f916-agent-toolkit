#!/bin/sh
# tests/hygiene.sh -- properties of the REPOSITORY, not of the programs.
#
# gate.sh and alert.sh test what the scripts do. This one tests what the tree
# is allowed to contain, because two of this repo's load-bearing claims are
# properties of the tree itself and nothing enforced them:
#
#   1. The shipped scripts are recorded executable. A file authored at 0644 and
#      committed over a 0755 original silently changes git's recorded mode; the
#      deploy then refuses with exit 126. That happened on 2026-09-02. The mode
#      that matters is the one in the INDEX, not the one in your checkout --
#      a fresh clone gets the recorded mode, and that is what a deploy sees.
#
#   2. No site-specific value is tracked. Every such value belongs in
#      ~/.witness-alert.conf or in the `op run` invocation, never in a file
#      here. This is the whole reason the config was externalised: a working
#      tree that deliberately differs from what you push is the shape that
#      leaks something the day someone runs `git add -A`.
#
# WHAT THIS CANNOT DO, said plainly so nobody reads a pass as more than it is:
# it matches SHAPES. Credentials, vault URIs, key material, mail addresses,
# network addresses and home paths have shapes. A bare private hostname does
# not -- a machine name is just a word -- so a hostname that is not part of a
# reachable address (no .ts.net, no .local, no IP) will pass this scan. Two
# such names were found in the prompt templates on 2026-09-04 by reading the
# tree, not by this script, and this script would not have caught them.
# Redaction still needs a human reading it.
#
# THE ESCAPE HATCH IS PER-LINE AND AUDITABLE. A line carrying the marker
# `hygiene:example` is skipped, because this file has to contain specimens of
# the shapes it hunts. The marker is confined to this file by a check below,
# so it cannot be sprinkled into the shipped scripts to silence a real finding,
# and `grep -rn hygiene:example` lists every exemption that exists.
#
# No secret, no network, no writes outside a temp directory.
#
#   sh tests/hygiene.sh              check this tree
#   sh tests/hygiene.sh --self-test  plant one value of each kind and REQUIRE
#                                    the scan to fail on every one

set -u

MARKER='hygiene'':example'

fails=0
checks=0

ok()    { checks=$((checks + 1)); echo "ok $checks - $1"; }
notok() { checks=$((checks + 1)); fails=$((fails + 1)); echo "not ok $checks - $1"; }

# --------------------------------------------------------------------------
# The allowlist, and why each entry is on it.
#
# These are values that LOOK site-specific and are deliberately published. Each
# is a decision somebody made in the open, not an oversight, so the scan has to
# know about them or it cries wolf every run and stops being read.
#
#   commonwealth@moxienerve.food  the reporting address in SECURITY.md.
#                                 Publishing it is the point of that file.
#   commonwealth.moxienerve.food  the identity's home page, linked from the README.
#   *@example.org/.com/.invalid   documentation placeholders.
#   *.noreply.github.com          GitHub's own non-delivering addresses.
#   1f916_sk_ + 64 zeros          the test suite's dummy credential. It matches the
#                                 real shape ON PURPOSE, because a dummy that does
#                                 not look like the real thing does not exercise the
#                                 code that handles the real thing. Only the all-zero
#                                 VALUE is exempt -- never the file it lives in.
#   const pem = "-----BEGIN ...    the ONE source line in 1f916-seed-to-sshkey.mjs
#                                 that writes a key's armor. The scan hunts a
#                                 committed KEY; a program that emits one is not
#                                 that, and the exemption is the writer's exact
#                                 line, which no key file contains -- so a real
#                                 key's header is still caught (the self-test
#                                 plants one and requires the catch).
# --------------------------------------------------------------------------
PEM_WRITER_LINE='const pem = "-----BEGIN OPENSSH PRIVATE KEY-----'   # hygiene:example
# ...and the ONE line in tests/sign.sh that asserts the emitted key is armored:
PEM_ASSERT_LINE="if grep -q -- '^-----BEGIN OPENSSH PRIVATE KEY-----\$' \"\$W/pem\""   # hygiene:example
allowed() {
  case "$1" in
    *"$MARKER"*)                     return 0 ;;
    *"$PEM_WRITER_LINE"*)            return 0 ;;
    *"$PEM_ASSERT_LINE"*)            return 0 ;;
    *commonwealth@moxienerve.food*)  return 0 ;;
    *commonwealth.moxienerve.food*)  return 0 ;;
    *@example.org*|*@example.com*|*@example.invalid*) return 0 ;;
    *noreply.github.com*)            return 0 ;;
    *1f916_sk_0000000000000000000000000000000000000000000000000000000000000000*) return 0 ;;
  esac
  return 1
}

# scan_list <file-with-one-path-per-line> <label>
# Every pattern here is a shape that has no business being committed.
# Each pattern line carries the marker: this file is full of its own quarry.
scan_list() {
  list=$1
  label=$2
  found=""

  patterns=$(cat <<'PATTERNS'
bearer credential	1f916_sk_[0-9a-f]{16,}	hygiene:example
vault reference with a real item	op://[^<[:space:]]	hygiene:example
private key block	BEGIN [A-Z ]*PRIVATE KEY	hygiene:example
tailnet address	[A-Za-z0-9-]+\.ts\.net	hygiene:example
mDNS hostname	[A-Za-z0-9-]+\.local[^A-Za-z0-9-]	hygiene:example
private IPv4	(192\.168\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3})\.[0-9]{1,3}	hygiene:example
absolute home path	/(home|Users)/[a-z][a-z0-9_-]+	hygiene:example
mail address	[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}	hygiene:example
PATTERNS
)

  while IFS='	' read -r desc regex _marker; do
    [ -n "$desc" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      allowed "$hit" && continue
      found="$found
  $desc: $hit"
    done <<EOF
$(while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -InE "$regex" "$f" 2>/dev/null | sed "s|^|$f:|"
  done < "$list")
EOF
  done <<EOF
$patterns
EOF

  if [ -n "$found" ]; then
    notok "$label -- site-specific values found:$found"
    return 1
  fi
  ok "$label"
  return 0
}

# --------------------------------------------------------------------------
EXPECT_755='1f916-gate witness-alert.sh 1f916-ssh-sign 1f916-scan tests/gate.sh tests/alert.sh tests/config-transport.sh tests/sign.sh tests/mutants.sh tests/stub-curl tests/hygiene.sh tests/scan.sh'

check_modes() {
  bad=''
  for f in $EXPECT_755; do
    mode=$(git ls-files -s -- "$f" | awk '{print $1}')
    [ -n "$mode" ] || { bad="$bad $f(untracked)"; continue; }
    [ "$mode" = '100755' ] || bad="$bad $f($mode)"
  done
  if [ -n "$bad" ]; then
    notok "executable files are recorded 100755 --$bad"
  else
    ok "executable files are recorded 100755"
  fi

  # The converse: nothing else should be executable. An unexpected +x is how a
  # data file starts being treated as a program.
  #
  # The listing goes through a temp file rather than a pipeline inside `$( )`,
  # and that is not style. bash 3.2 -- still /bin/sh on macOS, one of the two
  # machines this repo deploys to -- cannot parse a `case` nested inside a
  # command substitution: its scanner reads the `)` that closes a case pattern
  # as the one that closes the `$(`. POSIX allows it and shellcheck accepts it,
  # so Linux CI was green while this file would not parse on half the fleet.
  listing=$(mktemp) || exit 1
  git ls-files -s | awk '$1 == "100755" {print $4}' > "$listing"
  unexpected=''
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case " $EXPECT_755 " in
      *" $f "*) : ;;
      *) unexpected="$unexpected $f" ;;
    esac
  done < "$listing"
  rm -f "$listing"
  if [ -n "$unexpected" ]; then
    notok "no unexpected executables -- found:$unexpected"
  else
    ok "no unexpected executables"
  fi
}

# The escape hatch must not spread. If the marker appears anywhere but this
# file, someone has silenced the scan in a place it was meant to look.
check_marker_confined() {
  users=$(git grep -l -- "$MARKER" 2>/dev/null | grep -v '^tests/hygiene\.sh$')
  if [ -n "$users" ]; then
    notok "exemption marker confined to tests/hygiene.sh -- also in: $(echo "$users" | tr '\n' ' ')"
  else
    ok "exemption marker confined to tests/hygiene.sh"
  fi
}

# --------------------------------------------------------------------------
# The self-test. A scan that has never been shown finding something is not
# evidence that there is nothing to find.
#
# Every specimen below is deliberately FAKE -- example.invalid, documentation
# addresses, placeholder usernames. The first draft of this file used the real
# LAN address and the real tailnet name of the machine it protects, which would
# have committed exactly what the scan exists to keep out. Keep them fake.
self_test() {
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT INT TERM
  planted=0
  caught=0

  # name<TAB>specimen<TAB>marker. The marker is what keeps the tree scan from
  # flagging this block: these lines are the quarry, held on purpose.
  specimens=$(cat <<'SPECIMENS'
bearer	1f916_sk_9a4c17deadbeef2244668800aabbccddeeff00112233445566778899aabbccdd	hygiene:example
vault	BEARER=op://SomeVault/abc123def456/bearer	hygiene:example
key	-----BEGIN OPENSSH PRIVATE KEY-----	hygiene:example
tailnet	ssh someuser@somehost.tailnetexample.ts.net	hygiene:example
mdns	ping somehost.local 	hygiene:example
rfc1918	192.168.0.1	hygiene:example
cgnat	100.64.0.1	hygiene:example
homepath	/home/someuser/1f916-witness	hygiene:example
macpath	/Users/someuser/Projects	hygiene:example
mail	alerts@some-real-domain.net	hygiene:example
SPECIMENS
)

  while IFS='	' read -r name value _m; do
    [ -n "$name" ] || continue
    planted=$((planted + 1))
    printf '%s\n' "$value" > "$tmp/planted.txt"
    printf '%s\n' "$tmp/planted.txt" > "$tmp/list"
    # Subshell: a failure here is the EXPECTED result and must not be counted
    # against the run's own tally.
    if ( scan_list "$tmp/list" "self-test/$name" ) >/dev/null 2>&1; then
      echo "not ok - self-test/$name: scan PASSED on a planted value it must catch"
      fails=$((fails + 1))
    else
      caught=$((caught + 1))
      echo "ok - self-test/$name caught"
    fi
  done <<EOF
$specimens
EOF

  # And the converse: allowlisted values must NOT trip it, or the scan is
  # useless in a tree that legitimately contains them.
  for value in \
    "commonwealth@moxienerve.food" \
    "https://commonwealth.moxienerve.food/" \
    "you@example.org" \
    "321972176+commonwealth-1f916@users.noreply.github.com" \
    "1f916_sk_0000000000000000000000000000000000000000000000000000000000000000" \
    "$PEM_WRITER_LINE" \
    "$PEM_ASSERT_LINE"
  do
    printf '%s\n' "$value" > "$tmp/planted.txt"
    printf '%s\n' "$tmp/planted.txt" > "$tmp/list"
    if ( scan_list "$tmp/list" "allowlist" ) >/dev/null 2>&1; then
      echo "ok - allowlisted value not flagged: $value"
    else
      echo "not ok - allowlisted value flagged: $value"
      fails=$((fails + 1))
    fi
  done

  echo "self-test: $caught of $planted planted values caught"
  [ "$caught" = "$planted" ] || fails=$((fails + 1))
}

# --------------------------------------------------------------------------
case "${1:-}" in
  --self-test)
    self_test
    ;;
  "")
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
      echo "not ok - must run inside a git work tree (the recorded mode is the point)"
      exit 1
    }
    check_modes
    check_marker_confined
    tmpl=$(mktemp) || exit 1
    trap 'rm -f "$tmpl"' EXIT INT TERM
    git ls-files > "$tmpl"
    scan_list "$tmpl" "no site-specific values in tracked files"
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac

if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "PASSED"
exit 0
