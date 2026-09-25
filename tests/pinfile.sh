#!/bin/sh
# tests/pinfile.sh -- acceptance tests for 1f916-pin.
#
# NO SECRET AND NO NETWORK. Every key here is a throwaway made by ssh-keygen in
# a temp directory, and every signature is made by the real `ssh-keygen -Y
# sign`, because the point of the verifier is to agree with OpenSSH's own
# format: a signature this suite built by hand could share a misreading with
# the code under test.
#
# The order matters. Each negative case first asserts that its input really
# differs from the good one, then that the verifier refuses it with the exit
# code that means REFUSED (2) -- never "could not run" (3), which is kept for
# a missing input. A detector shown only passing is not evidence.
#
# Usage: sh tests/pinfile.sh

set -u

command -v ssh-keygen >/dev/null 2>&1 || { echo "not ok - ssh-keygen not found"; exit 1; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN_TOOL="$ROOT/1f916-pin"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM HUP

fails=0
n=0
ok()    { n=$((n + 1)); echo "ok $n - $1"; }
notok() { n=$((n + 1)); fails=$((fails + 1)); echo "not ok $n - $1"; }

# run <expected-exit> <label> <args...>  -- output kept in $W/out
run() {
  want=$1; label=$2; shift 2
  python3 "$PIN_TOOL" "$@" > "$W/out" 2>&1
  got=$?
  if [ "$got" = "$want" ]; then ok "$label (exit $got)"; else notok "$label (exit $got, wanted $want): $(cat "$W/out")"; fi
}

differs() {
  if cmp -s "$1" "$2"; then notok "$3 -- the tampered input is IDENTICAL to the good one"; return 1; fi
  ok "$3 -- the tampered input differs"
}

# Two throwaway keys: the trusted one and a stranger.
ssh-keygen -q -t ed25519 -N '' -C trusted -f "$W/trusted" || exit 1
ssh-keygen -q -t ed25519 -N '' -C stranger -f "$W/stranger" || exit 1
FP=$(ssh-keygen -l -E sha256 -f "$W/trusted.pub" | awk '{print $2}')
FP_STRANGER=$(ssh-keygen -l -E sha256 -f "$W/stranger.pub" | awk '{print $2}')

# The same trusted key as the registry serves it: {"keys":[{"x": base64url}]}.
python3 - "$W/trusted.pub" > "$W/keys.json" <<'PY'
import base64, json, struct, sys
blob = base64.b64decode(open(sys.argv[1]).read().split()[1])
n = struct.unpack(">I", blob[:4])[0]
raw = blob[4 + n + 4:]
x = base64.urlsafe_b64encode(raw).decode().rstrip("=")
print(json.dumps({"keys": [{"kty": "OKP", "crv": "Ed25519", "x": x, "status": "active"}]}))
PY

mkdir -p "$W/tools"
printf '#!/bin/sh\necho one\n' > "$W/tools/tool-a"
printf '#!/bin/sh\necho two\n' > "$W/tools/tool-b"
dig() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
{
  echo "1f916-pin v1"
  echo "serial 7"
  echo "commit 0123456789abcdef0123456789abcdef01234567"
  echo "tag v2026.01.01"
  echo "file tool-a $(dig "$W/tools/tool-a")"
  echo "file tool-b $(dig "$W/tools/tool-b")"
} > "$W/PIN"

sign() { # sign <key> <namespace> <file> -> <file>.sig
  rm -f "$3.sig"
  ssh-keygen -q -Y sign -f "$1" -n "$2" "$3" 2>/dev/null
}

# ---- the verifier's own vectors and controls
run 0 "self-test: RFC 8032 vectors verify and every control refuses" self-test

# ---- fingerprints agree with OpenSSH's own
python3 "$PIN_TOOL" fingerprint --pubkey "$W/trusted.pub" > "$W/fp1"
python3 "$PIN_TOOL" fingerprint --key-json "$W/keys.json" > "$W/fp2"
if grep -qF "\"$FP\"" "$W/fp1" && grep -qF "\"$FP\"" "$W/fp2"; then
  ok "fingerprint of both key sources equals ssh-keygen -l"
else
  notok "fingerprint disagrees with ssh-keygen -l ($FP): $(cat "$W/fp1" "$W/fp2")"
fi

# ---- the good case, both key sources, with and without the file check
sign "$W/trusted" 1f916-pin "$W/PIN"; cp "$W/PIN.sig" "$W/good.sig"
run 0 "good pin, registry key document" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json" --fingerprint "$FP"
if grep -q '"commit": "0123456789abcdef0123456789abcdef01234567"' "$W/out"; then
  ok "a PASS prints the commit it verified"
else
  notok "a PASS did not print the commit"
fi
run 0 "good pin, OpenSSH public key" verify --pin "$W/PIN" --sig "$W/good.sig" --pubkey "$W/trusted.pub" --fingerprint "$FP"
run 0 "good pin and the files it names" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json" --fingerprint "$FP" --dir "$W/tools"
run 0 "serial at the minimum" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json" --fingerprint "$FP" --min-serial 7

# ---- refusals (exit 2), each input proven different first
cp "$W/PIN" "$W/PIN.flip"
python3 - "$W/PIN.flip" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
i = b.index(b"serial 7") + 7; b[i] = ord("8")
open(p, "wb").write(bytes(b))
PY
differs "$W/PIN" "$W/PIN.flip" "one byte of the pin changed" &&
run 2 "a pin changed after signing is refused" verify --pin "$W/PIN.flip" --sig "$W/good.sig" --key-json "$W/keys.json" --fingerprint "$FP"
if grep -q '"pin"' "$W/out"; then notok "a FAIL printed pin contents"; else ok "a FAIL prints no pin contents"; fi

cp "$W/PIN" "$W/PIN.git"; sign "$W/trusted" git "$W/PIN.git"
differs "$W/good.sig" "$W/PIN.git.sig" "a signature in namespace git" &&
run 2 "a signature made for git (wrong namespace) is refused" verify --pin "$W/PIN" --sig "$W/PIN.git.sig" --key-json "$W/keys.json" --fingerprint "$FP"

cp "$W/PIN" "$W/PIN.str"; sign "$W/stranger" 1f916-pin "$W/PIN.str"
differs "$W/good.sig" "$W/PIN.str.sig" "a signature by another key" &&
run 2 "a pin signed by a key that is not the trusted one is refused" verify --pin "$W/PIN" --sig "$W/PIN.str.sig" --key-json "$W/keys.json" --fingerprint "$FP"
run 2 "trusting the stranger's fingerprint against the registry's key is refused" verify --pin "$W/PIN" --sig "$W/PIN.str.sig" --key-json "$W/keys.json" --fingerprint "$FP_STRANGER"

python3 - "$W/good.sig" "$W/tampered.sig" <<'PY'
import base64, sys
lines = open(sys.argv[1]).read().strip().splitlines()
blob = bytearray(base64.b64decode("".join(lines[1:-1])))
blob[-10] ^= 0x01            # inside the 64-byte Ed25519 signature value
body = base64.b64encode(bytes(blob)).decode()
out = [lines[0]] + [body[i:i + 70] for i in range(0, len(body), 70)] + [lines[-1]]
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY
differs "$W/good.sig" "$W/tampered.sig" "one bit of the signature value flipped" &&
run 2 "a tampered signature value is refused" verify --pin "$W/PIN" --sig "$W/tampered.sig" --key-json "$W/keys.json" --fingerprint "$FP"

run 2 "a serial below the minimum (rollback) is refused" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json" --fingerprint "$FP" --min-serial 8

cp "$W/tools/tool-b" "$W/tool-b.orig"; echo "# changed" >> "$W/tools/tool-b"
differs "$W/tool-b.orig" "$W/tools/tool-b" "a pinned file changed" &&
run 2 "a pinned file whose digest differs is refused" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json" --fingerprint "$FP" --dir "$W/tools"
cp "$W/tool-b.orig" "$W/tools/tool-b"

printf '1f916-pin v1\r\nserial 1\r\n' > "$W/PIN.crlf"; sign "$W/trusted" 1f916-pin "$W/PIN.crlf"
run 2 "a validly signed but malformed pin is refused" verify --pin "$W/PIN.crlf" --sig "$W/PIN.crlf.sig" --key-json "$W/keys.json" --fingerprint "$FP"

# ---- could not run (exit 3): nothing decided
run 3 "a missing signature file is could-not-run, not a refusal" verify --pin "$W/PIN" --sig "$W/absent.sig" --key-json "$W/keys.json" --fingerprint "$FP"
: > "$W/empty.json"
run 3 "an empty key document is could-not-run" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/empty.json" --fingerprint "$FP"
echo '{"keys":[{"crv":"Ed25519","x":"AAAA","status":"revoked"}]}' > "$W/revoked.json"
run 3 "a key document with no active key is could-not-run" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/revoked.json" --fingerprint "$FP"
mv "$W/tools/tool-a" "$W/tool-a.away"
run 3 "a pinned file that is missing is could-not-run" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json" --fingerprint "$FP" --dir "$W/tools"
mv "$W/tool-a.away" "$W/tools/tool-a"

# ---- tag-verify: a signed git tag checked with the same verifier ------------
# The live specimen first: a real signed tag of this repository, as
# `git cat-file tag` served it, against the key the registry published for the
# identity. OpenSSH agreed on the same bytes when the fixture was captured
# (ssh-keygen -Y verify, namespace git); this suite re-checks that where
# ssh-keygen exists, so the two verifiers are compared on every run.
FIXT="$ROOT/tests/fixtures/pin"
REGFP=SHA256:q2yRbCWjFFYblk+Fb2yBiKBpl+PLM1SnhJX/veRUsOs
run 0 "live tag v2026.09.23.2 verifies against the registry's key" tag-verify --tag-object "$FIXT/tag-v2026.09.23.2" --key-json "$FIXT/keys-commonwealth.json" --fingerprint "$REGFP" --expect-object e0429dcd665ddd5253234d4ae583f207a9bb6823 --expect-tag v2026.09.23.2
python3 - "$FIXT/keys-commonwealth.json" "$FIXT/tag-v2026.09.23.2" "$W" <<'PY'
import base64, json, struct, sys
x = json.load(open(sys.argv[1]))["keys"][0]["x"]
raw = base64.urlsafe_b64decode(x + "=" * (-len(x) % 4))
blob = struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32) + raw
open(sys.argv[3] + "/reg-allowed", "w").write('c namespaces="git" ssh-ed25519 ' + base64.b64encode(blob).decode() + "\n")
d = open(sys.argv[2], "rb").read()
i = d.rindex(b"-----BEGIN SSH SIGNATURE-----")
open(sys.argv[3] + "/live.payload", "wb").write(d[:i])
open(sys.argv[3] + "/live.sig", "wb").write(d[i:])
PY
if ssh-keygen -Y verify -f "$W/reg-allowed" -I c -n git -s "$W/live.sig" < "$W/live.payload" >/dev/null 2>&1; then
  ok "OpenSSH agrees: the live tag verifies with ssh-keygen -Y verify too"
else
  notok "OpenSSH does not verify the live tag fixture"
fi

cp "$FIXT/tag-v2026.09.23.2" "$W/live.flip"
python3 - "$W/live.flip" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
i = b.index(b"key possession"); b[i] = ord("K")
open(p, "wb").write(bytes(b))
PY
differs "$FIXT/tag-v2026.09.23.2" "$W/live.flip" "one byte of the live tag's message changed" &&
run 2 "negative control: the live tag with one changed byte is refused" tag-verify --tag-object "$W/live.flip" --key-json "$FIXT/keys-commonwealth.json" --fingerprint "$REGFP"
if grep -q '"tag"' "$W/out"; then notok "a FAIL printed tag contents"; else ok "a FAIL prints no tag contents"; fi
run 2 "the live tag against a commit it does not name is refused" tag-verify --tag-object "$FIXT/tag-v2026.09.23.2" --key-json "$FIXT/keys-commonwealth.json" --fingerprint "$REGFP" --expect-object 0123456789abcdef0123456789abcdef01234567
run 2 "the live tag under another expected name is refused" tag-verify --tag-object "$FIXT/tag-v2026.09.23.2" --key-json "$FIXT/keys-commonwealth.json" --fingerprint "$REGFP" --expect-tag v2026.09.23.1
run 2 "the live tag against the throwaway key is refused" tag-verify --tag-object "$FIXT/tag-v2026.09.23.2" --key-json "$W/keys.json" --fingerprint "$FP"

# Tags made here by git itself, signed with the throwaway keys. The operator's
# own git config is kept out: a global gpg.ssh.program or signing key would
# sign with something that is not the key under test.
git init -q "$W/repo"
( export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  cd "$W/repo" && git config gpg.ssh.program ssh-keygen &&
  git config user.name tester && git config user.email tester@example.org &&
  git config gpg.format ssh && git config user.signingkey "$W/trusted" &&
  git commit -q --allow-empty -m one &&
  git tag -s -m "signed by the trusted key" good-tag &&
  git -c user.signingkey="$W/stranger" tag -s -m "signed by a stranger" stranger-tag &&
  git tag -a -m "annotated, unsigned" plain-tag &&
  git cat-file tag good-tag > "$W/tag.good" &&
  git cat-file tag stranger-tag > "$W/tag.stranger" &&
  git cat-file tag plain-tag > "$W/tag.plain" &&
  git rev-parse HEAD > "$W/head" ) || notok "could not build the git tag fixtures"
run 0 "a tag git signed with the trusted key verifies" tag-verify --tag-object "$W/tag.good" --pubkey "$W/trusted.pub" --fingerprint "$FP" --expect-object "$(cat "$W/head")" --expect-tag good-tag
run 2 "a tag signed by a stranger is refused" tag-verify --tag-object "$W/tag.stranger" --pubkey "$W/trusted.pub" --fingerprint "$FP"
run 2 "an annotated tag with no signature is refused" tag-verify --tag-object "$W/tag.plain" --pubkey "$W/trusted.pub" --fingerprint "$FP"

# The same payload signed in the pin namespace must not pass as a tag signature.
python3 - "$W/tag.good" "$W" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
i = d.rindex(b"-----BEGIN SSH SIGNATURE-----")
open(sys.argv[2] + "/tag.payload", "wb").write(d[:i])
PY
sign "$W/trusted" 1f916-pin "$W/tag.payload"
cat "$W/tag.payload" "$W/tag.payload.sig" > "$W/tag.pinns"
differs "$W/tag.good" "$W/tag.pinns" "the tag re-signed in namespace 1f916-pin" &&
run 2 "a tag signature made in the 1f916-pin namespace is refused" tag-verify --tag-object "$W/tag.pinns" --pubkey "$W/trusted.pub" --fingerprint "$FP"
run 2 "and a pin signature can never be a tag signature: git namespace refused by verify" verify --pin "$W/tag.payload" --sig "$W/tag.payload.sig" --pubkey "$W/trusted.pub" --fingerprint "$FP"

run 3 "a missing tag object is could-not-run" tag-verify --tag-object "$W/absent.tag" --pubkey "$W/trusted.pub" --fingerprint "$FP"
run 64 "tag-verify with no fingerprint is a usage error" tag-verify --tag-object "$W/tag.good" --pubkey "$W/trusted.pub"
run 64 "a flag that belongs to verify is refused by tag-verify" tag-verify --tag-object "$W/tag.good" --pubkey "$W/trusted.pub" --fingerprint "$FP" --dir "$W/tools"

# ---- usage (exit 64)
run 64 "no fingerprint is a usage error" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json"
run 64 "both key sources at once is a usage error" verify --pin "$W/PIN" --sig "$W/good.sig" --key-json "$W/keys.json" --pubkey "$W/trusted.pub" --fingerprint "$FP"

echo "1..$n"
[ "$fails" -eq 0 ] || { echo "$fails of $n FAILED"; exit 1; }
echo "all $n passed"
