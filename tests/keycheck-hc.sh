#!/bin/sh
# tests/keycheck-hc.sh -- sitting/keycheck-hc.sh with op, the gate and the
# healthchecks read stubbed. What is tested: the folder argument is refused
# unless it is a dated 1f916-YYYY-MM-DD folder; the log records the gate's
# verdict and every exit status; and the vault reference never reaches the log.
set -u
here=$(cd "$(dirname "$0")" && pwd)
S="$here/../sitting/keycheck-hc.sh"
fail=0
expect() {
  name=$1; shift
  if "$@"; then echo "ok - $name"; else echo "not ok - $name"; fail=1; fi
}
lacks() { if printf '%s\n' "$1" | grep -q "$2"; then return 1; fi; return 0; }
has() { printf '%s\n' "$1" | grep -q "$2"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home/.config/1f916" "$tmp/bin" "$tmp/1f916-2026-01-02" "$tmp/notdated"
REF='op://<SPECIMEN-vault>/<SPECIMEN-item>'
printf "GATE_ITEM_REF='%s'\n" "$REF" > "$tmp/home/.config/1f916/sitting.env"
# op stub: drop everything up to --, then run the child with the referenced
# variables replaced by placeholders, as op run does with real values.
cat > "$tmp/bin/op" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done
shift
BEARER=x ED25519_PRIV=x HANDLE=x CITIZEN=x exec "$@"
STUB
cat > "$tmp/bin/gate" <<'STUB'
#!/bin/sh
[ "$1" = key-check ] || exit 9
echo "gate: PASS (hash stub)"; echo "key: PASS"; echo "nothing sent"
STUB
cat > "$tmp/bin/hc" <<'STUB'
#!/bin/sh
echo "VERDICT PASS" > "$1/hc-status.stub.log"
STUB
chmod +x "$tmp/bin/op" "$tmp/bin/gate" "$tmp/bin/hc"

run() { HOME="$tmp/home" PATH="$tmp/bin:$PATH" GATE="$tmp/bin/gate" HC_STATUS="$tmp/bin/hc" sh "$S" "$@"; }

run "$tmp/notdated" 2>/dev/null; rc=$?
expect "an undated folder is refused" [ "$rc" = 2 ]
expect "nothing written for a refused folder" [ ! -e "$tmp/notdated/keycheck.log" ]
run 2>/dev/null; rc=$?
expect "no argument is refused" [ "$rc" = 2 ]

run "$tmp/1f916-2026-01-02"; rc=$?
log=$(cat "$tmp/1f916-2026-01-02/keycheck.log")
expect "dated folder exits 0" [ "$rc" = 0 ]
expect "gate verdict logged" has "$log" '^gate: PASS'
expect "key_check_exit logged" has "$log" '^key_check_exit=0$'
expect "op_exit logged" has "$log" '^op_exit=0$'
expect "hc_exit logged" has "$log" '^hc_exit=0$'
expect "healthchecks read ran in the folder" [ -e "$tmp/1f916-2026-01-02/hc-status.stub.log" ]
expect "vault reference not in the log" lacks "$log" SPECIMEN

rm "$tmp/home/.config/1f916/sitting.env"
mkdir -p "$tmp/1f916-2026-01-03"
run "$tmp/1f916-2026-01-03"; rc=$?
expect "missing sitting.env exits 3" [ "$rc" = 3 ]

expect "launcher parses" sh -n "$S"
if [ "$fail" = 0 ]; then echo "PASSED"; else echo "FAILED"; exit 1; fi
