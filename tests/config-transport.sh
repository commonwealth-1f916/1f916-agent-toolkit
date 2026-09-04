#!/bin/sh
# tests/config-transport.sh -- does the credential actually stay out of argv,
# against the REAL curl on this host rather than against a double?
#
# tests/gate.sh proves the gate CALLS curl with a config on a pipe. It cannot
# prove that real curl reads that config, that the header arrives, or that the
# value is invisible to ps(1) -- its curl is a shell script. This does, with a
# throwaway HTTP server on loopback. Still no secret (the token is a dummy) and
# still no network beyond 127.0.0.1.
#
# The control matters more than the test: it runs the OLD pattern -H
# "Authorization: ..." through the same observation and REQUIRES ps to find the
# token. A check for a secret in `ps` that has never been shown finding one is
# not evidence of anything.

set -u

command -v python3 >/dev/null 2>&1 || { printf '# no python3: skipping the transport test\n'; exit 0; }
command -v curl    >/dev/null 2>&1 || { printf '# no curl: skipping the transport test\n'; exit 0; }

W=$(mktemp -d) || exit 1
SRV=""
# `wait` after the kill, so the shell does not print its own "Terminated"
# job notice into a passing test's output. Output that reads like a failure in
# a green run is its own small defect.
cleanup() {
  if [ -n "$SRV" ]; then kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; fi
  rm -rf "$W"
}
trap cleanup EXIT

PORT=$(( 18000 + $$ % 20000 ))
TOKEN='1f916_sk_notarealtokendeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbe'

# The server goes in a FILE rather than a heredoc piped to a backgrounded
# python. `cmd <<EOF &` is not portable: macOS /bin/sh (bash 3.2) does not
# attach the document to the backgrounded job, and the body ends up being read
# as commands -- which is exactly what happened the first time this ran there,
# with the gate suite still green beside it.
cat > "$W/server.py" <<'SERVER'
import sys, time, json, http.server
d, port = sys.argv[1], int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def _done(self, code, payload=b'{"ok":1}'):
        with open(d + '/headers', 'a') as f:
            f.write(json.dumps(dict(self.headers)) + "\n")
        self.send_response(code)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def do_GET(self):
        if self.path.startswith('/slow'):
            time.sleep(3)
        self._done(200)
    def do_POST(self):
        n = int(self.headers.get('content-length', 0))
        open(d + '/body', 'wb').write(self.rfile.read(n))
        self._done(201)
    def log_message(self, *a):
        pass
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
SERVER
python3 "$W/server.py" "$W" "$PORT" >/dev/null 2>&1 &
SRV=$!

# Wait for the server rather than sleeping a guessed amount.
up=0
i=0
while [ "$i" -lt 50 ]; do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/ping"; then up=1; break; fi
  i=$((i+1)); sleep 0.2
done
if [ "$up" != "1" ]; then
  printf 'not ok 1 - the loopback server never came up on port %s\n' "$PORT"
  printf '# a transport test that cannot reach its own server proves nothing; failing rather than skipping\n'
  exit 1
fi

pass=0; fail=0; n=0
ok()  { n=$((n+1)); pass=$((pass+1)); printf 'ok %d - %s\n' "$n" "$1"; }
nok() { n=$((n+1)); fail=$((fail+1)); printf 'not ok %d - %s\n' "$n" "$1"
        [ $# -gt 1 ] && printf '  # %s\n' "$2"; }

printf '# real-curl transport test on port %s\n' "$PORT"

# --- 1. the pattern the gate now uses -------------------------------------
echo '{"hello":"world"}' > "$W/body.json"
status=$(BEARER="$TOKEN" awk 'BEGIN {
    s = ENVIRON["BEARER"]
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
    printf "header = \"Authorization: Bearer %s\"\n", s
  }' | curl -s --max-time 10 -K - -o "$W/out" -w '%{http_code}' \
        -H 'Content-Type: application/json' -X POST \
        --data-binary @"$W/body.json" "http://127.0.0.1:$PORT/api/seal")

if [ "$status" = "201" ]; then ok "1. real curl accepts a config on stdin"
else nok "1. real curl accepts a config on stdin" "status was '$status'"; fi
if grep -qF "Bearer $TOKEN" "$W/headers"; then ok "1. and the Authorization header reached the server"
else nok "1. and the Authorization header reached the server" "no such header received"; fi
if grep -qF 'hello' "$W/body"; then ok "1. and the body still arrived from its file"
else nok "1. and the body still arrived from its file" "body missing"; fi

# --- 2. is it invisible to ps(1) while the call is in flight? --------------
# Record only the CURL command lines. Scanning the whole process table looks
# more thorough and is worse: it picks up whatever shell or CI harness happens
# to have the dummy token in its own arguments -- which it did, the first time
# this test ran, and reported a failure that had nothing to do with curl. The
# claim under test is about curl's argv, so that is what to look at.
snapshot() {  # snapshot <outfile>
  sleep 1
  { ps -A -o args= 2>/dev/null || ps ax -o command= 2>/dev/null; } | grep curl > "$1" 2>/dev/null
  [ -f "$1" ] || : > "$1"
}

BEARER="$TOKEN" awk 'BEGIN {
    s = ENVIRON["BEARER"]
    printf "header = \"Authorization: Bearer %s\"\n", s
  }' | curl -s --max-time 10 -K - -o /dev/null "http://127.0.0.1:$PORT/slow" &
CURL_NEW=$!
snapshot "$W/ps_new"
wait "$CURL_NEW" 2>/dev/null

curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" -o /dev/null "http://127.0.0.1:$PORT/slow" &
CURL_OLD=$!
snapshot "$W/ps_old"
wait "$CURL_OLD" 2>/dev/null

# THE CONTROL FIRST. If ps cannot see the token in the old pattern then this
# whole check is incapable of failing and proves nothing about the new one.
if grep -qF "$TOKEN" "$W/ps_old"
then ok "2. CONTROL: ps DOES see the token in curl's argv when it is passed with -H"
else nok "2. CONTROL: ps DOES see the token in curl's argv when it is passed with -H" \
        "the observation is blind here, so the result below is not evidence"; fi

if grep -qF "$TOKEN" "$W/ps_new"
then nok "2. the config-on-a-pipe keeps the token out of ps" "found it in the process list"
else ok "2. the config-on-a-pipe keeps the token out of ps"; fi

printf '# %d tests, %d passed, %d failed\n' "$n" "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
