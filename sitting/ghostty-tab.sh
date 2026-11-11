#!/bin/sh
# sitting/ghostty-tab.sh -- open one hashed script in a new Ghostty tab on the
# Mac, the only way an attended sitting opens a visible step (a signing, a
# launcher under `op run`, anything a 1Password prompt has to be seen for).
#
#   sh ghostty-tab.sh SCRIPT SHA256 [LOG]
#
# Before 2026-11 every visible step was an AppleScript block copied by hand,
# and the one-off scripts inside it lacked the Homebrew PATH (one failed with
# `op: command not found`). This is that block, once:
#
#   - SCRIPT must sit under /tmp/1f916-<date>/ (or /private/tmp/1f916-<date>/)
#     or under ~/Projects, and its path, like LOG's, may carry only
#     A-Z a-z 0-9 / _ . - : the path is placed inside a quoted shell word
#     inside an AppleScript string, and nothing else is safe in both.
#   - SCRIPT's sha-256 must equal SHA256, so the bytes the sitting hashed are
#     the bytes the tab runs. A mismatch opens nothing.
#   - The tab runs /bin/sh with /opt/homebrew/bin and /usr/local/bin on PATH,
#     then SCRIPT, then prints its exit code and, when LOG is named, the
#     log's last lines. `wait after command` keeps the tab open to be read.
#   - A new tab in the front Ghostty window; a new window only when none is
#     open. Never `open -na Ghostty`, which opens a window every time.
#
# A sitting calls this with one osascript `do shell script` and reads the
# script's own log; this program's exit status says only whether the tab was
# asked for (docs/bridged-sittings.md (h)). It holds and prints no secret.
#
# Exit codes: 0 the tab was asked for; 2 usage; 3 refused (path, hash, no
# Ghostty, no osascript).
set -u

fail() { printf 'ghostty-tab: %s\n' "$1" >&2; exit "${2:-3}"; }
[ $# -eq 2 ] || [ $# -eq 3 ] || fail "usage: sh ghostty-tab.sh SCRIPT SHA256 [LOG]" 2
SCRIPT=$1; WANT=$2; LOG=${3:-}

safe_path() {  # safe_path WHAT PATH
  case "$2" in
    ''|*[!A-Za-z0-9/_.-]*) fail "$1 path carries a character outside A-Z a-z 0-9 / _ . - : $2" ;;
  esac
  case "$2" in
    /*) ;;
    *) fail "$1 path is not absolute: $2" ;;
  esac
  case "$2" in
    */../*|*/..|*/./*|*//*) fail "$1 path has a dot or empty segment: $2" ;;
  esac
  case "$2" in
    /tmp/1f916-*/*|/private/tmp/1f916-*/*) ;;
    "$HOME"/Projects/*) ;;
    *) fail "$1 path is outside /tmp/1f916-<date>/ and ~/Projects: $2" ;;
  esac
}

case "${HOME:-}" in
  ''|*[!A-Za-z0-9/_.-]*) fail "HOME is unset or carries a character this script cannot quote" ;;
esac
safe_path script "$SCRIPT"
[ -z "$LOG" ] || safe_path log "$LOG"
[ -f "$SCRIPT" ] || fail "script not found: $SCRIPT"
case "$WANT" in
  *[!0-9a-f]*|'') fail "SHA256 is not lowercase hex" ;;
esac
[ ${#WANT} -eq 64 ] || fail "SHA256 is not 64 hex characters"

if command -v shasum >/dev/null 2>&1; then
  GOT=$(shasum -a 256 "$SCRIPT" | cut -c1-64)
elif command -v sha256sum >/dev/null 2>&1; then
  GOT=$(sha256sum "$SCRIPT" | cut -c1-64)
else
  fail "neither shasum nor sha256sum on PATH"
fi
[ "$GOT" = "$WANT" ] || fail "sha-256 mismatch, nothing opened: $SCRIPT is $GOT"

command -v osascript >/dev/null 2>&1 || fail "osascript not found: this runs on the Mac"

# The command the tab runs. Single quotes inside are safe: every path was
# held to an alphabet with no quote, space, dollar or backslash in it.
INNER="PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; export PATH; /bin/sh $SCRIPT; code=\$?; echo; echo ghostty-tab: exit \$code"
[ -z "$LOG" ] || INNER="$INNER; echo ghostty-tab: tail of $LOG; tail -n 12 $LOG"
INNER="$INNER; exit \$code"

osascript - "$INNER" <<'APPLESCRIPT' || fail "osascript could not open the tab"
on run argv
  set inner to item 1 of argv
  tell application "Ghostty"
    set cfg to new surface configuration
    set command of cfg to "/bin/sh -c " & quoted form of inner
    set wait after command of cfg to true
    if (count of windows) > 0 then
      new tab in front window with configuration cfg
    else
      new window with configuration cfg
    end if
  end tell
end run
APPLESCRIPT
printf 'ghostty-tab: opened %s (%s)\n' "$SCRIPT" "$GOT"
exit 0
