#!/bin/bash
# run.sh — behavioural tests for magicmousefix.
#
# None of these touch the mouse. Every case either stops in argument parsing (before any
# HID call) or asserts something about the source itself. Safe to run at any time, with or
# without sudo.
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$HERE/magicmousefix
SRC=$HERE/src/magicmousefix.c

pass=0; fail=0

ok()   { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

# exit_is <expected> <label> -- <args...>
exit_is() {
  local want=$1 label=$2; shift 3
  "$BIN" "$@" >/dev/null 2>&1
  local got=$?
  [ "$got" -eq "$want" ] && ok "$label (exit $got)" || bad "$label (want exit $want, got $got)"
}

# exit_not <unwanted> <label> -- <args...>
exit_not() {
  local nope=$1 label=$2; shift 3
  "$BIN" "$@" >/dev/null 2>&1
  local got=$?
  [ "$got" -ne "$nope" ] && ok "$label (exit $got)" || bad "$label (should not exit $nope)"
}

# The source guarantees below are about CODE, not prose. Grepping the raw file makes the
# word "connect" in a comment look like a network call, so strip the comments first.
CODE=$(mktemp -t magicmousefix-code)
trap 'rm -f "$CODE"' EXIT
awk -f "$HERE/tests/strip-comments.awk" "$SRC" > "$CODE" \
  || { echo "could not strip comments from $SRC" >&2; exit 1; }
[ -s "$CODE" ] || { echo "stripping comments from $SRC produced nothing" >&2; exit 1; }

src_has() {
  grep -qE "$1" "$CODE" && ok "$2" || bad "$2"
}
src_lacks() {
  grep -qE "$1" "$CODE" && bad "$3" || ok "$3"
}

[ -x "$BIN" ] || { echo "build first: make build" >&2; exit 1; }

echo "argument validation (nothing reaches the device)"
exit_is  2 "unknown flag is rejected"                 -- --nope
exit_is  2 "--heartbeat rejects a non-number"         -- --agent --heartbeat abc
exit_is  2 "--heartbeat rejects below the floor"      -- --agent --heartbeat 1
exit_is  2 "--heartbeat rejects above the ceiling"    -- --agent --heartbeat 999999
exit_is  2 "--heartbeat rejects a negative"           -- --agent --heartbeat -60
exit_is  2 "--heartbeat rejects trailing junk"        -- --agent --heartbeat 60s
exit_is  2 "--pid rejects a non-number"               -- --pid wat
exit_is  2 "--pid rejects out of range"               -- --pid 0x1FFFF
exit_is  2 "--pid rejects zero"                       -- --pid 0
exit_is  2 "--dry-run and --agent are exclusive"      -- --dry-run --agent
exit_is  2 "--heartbeat alone is refused, not ignored" -- --heartbeat 60
exit_not 2 "--pid accepts a valid product id"         -- --dry-run --pid 0x0269

echo
echo "privilege behaviour"
# Unprivileged, the exact code depends on whether a Magic Mouse is connected right now:
# with one attached, IOHIDManagerOpen is refused and we exit 3; with none, the open
# succeeds trivially, nothing matches, and we exit 1. Asserting either specific value
# makes the suite pass or fail according to whether the mouse happens to be awake.
# The invariant that actually matters is that an unprivileged run never reports success.
if [ "$(id -u)" -eq 0 ]; then
  exit_not 2 "root gets past argument parsing"        -- --dry-run
else
  exit_not 0 "an unprivileged dry run never succeeds" -- --dry-run
  exit_not 0 "an unprivileged send never succeeds"    --
fi

echo
echo "reporting"
# With no mouse attached, IOHIDManagerCopyDevices returns NULL, which used to make both
# modes exit silently. A dry run must always say what it did, especially "nothing".
out=$("$BIN" --dry-run 2>&1)
case "$out" in
  *"dry run:"*) ok "a dry run reports its summary even with no mouse attached" ;;
  *)            bad "a dry run reports its summary even with no mouse attached" ;;
esac
case "$out" in
  *"would send"*) bad "a dry run with no mouse claims nothing was sent to" ;;
  *)              ok  "a dry run with no mouse claims nothing was sent to" ;;
esac

echo
echo "source guarantees"
src_has   'IOHIDManagerSetDeviceMatchingMultiple'  "matching is restricted to an allow-list"
src_lacks 'IOHIDManagerSetDeviceMatching[[:space:]]*\([^,]*,[[:space:]]*NULL' '' \
          "does not open every HID device"
src_lacks '\b(socket|connect|getaddrinfo|CFURLCreate|NSURL|curl_)[[:space:]]*\(' '' \
          "makes no network calls"
src_lacks '\b(fopen|fwrite|unlink|remove|mkdir)[[:space:]]*\(' '' "writes no files"
src_lacks '\b(system|popen|fork|exec[lv][ep]?)[[:space:]]*\(' '' "spawns no processes"
src_lacks 'IOHIDDeviceRegisterInputReportCallback|IOHIDManagerRegisterInputValueCallback' '' \
          "registers no input callback (reads no keystrokes or clicks)"
src_has   'kIOHIDVendorIDKey'                      "re-checks the vendor id on the device"
src_has   'PRODUCT_SUBSTRING'                      "re-checks the product name on the device"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
