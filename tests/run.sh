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
# modes exit silently. A dry run must always say what it did — either its summary, or why
# it could not look. Which of the two comes out depends on whether a mouse is connected
# and on privilege, so asserting one specific message would make this pass or fail with
# the state of the hardware; "never silent" is the part that is always true.
out=$("$BIN" --dry-run 2>&1)
case "$out" in
  *"dry run:"*|*"No HID access"*) ok  "a dry run always reports what it did" ;;
  *)                              bad "a dry run always reports what it did" ;;
esac
# "would send" is CORRECT output when a mouse is attached and we have the privilege to
# see it — the Operator's own privileged run prints it four times. Asserting its absence
# unconditionally fails `sudo make test` on a working machine, marking right behaviour as
# a defect. What must hold in every state is that a dry run never claims to have sent.
case "$out" in
  *"nothing sent"*|*"No HID access"*) ok  "a dry run never reports having sent" ;;
  *)                                  bad "a dry run never reports having sent" ;;
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
# The same mouse reports 0x05AC over USB and 0x004C (Apple's Bluetooth SIG id) over
# Bluetooth. Matching only the first finds nothing on a Bluetooth Magic Mouse.
src_has   '0x05AC'                                 "allow-list covers the USB vendor id"
src_has   '0x004C'                                 "allow-list covers the Bluetooth vendor id"
src_has   'kIOHIDProductIDKey'                     "re-checks the product id on the device"
# Identity is the vendor and product id. The product string is the owner's editable
# Bluetooth name, so any code path that REJECTS a device for its name silently refuses to
# fix a renamed mouse — which is most mice that are not this developer's.
#
# Assert this on the BODY of is_target, not on the whole file: the decision function must
# not read the product string at all. An earlier version of this check grepped for
# `strstr(... kIOHIDProductKey` on one line and so passed on the very gate it forbade,
# which had the two tokens on separate lines.
is_target_body=$(awk '/^static int is_target\(/,/^}/' "$CODE")
if [ -z "$is_target_body" ]; then
  bad "is_target() could be located for inspection"
else
  ok "is_target() could be located for inspection"
  case "$is_target_body" in
    *kIOHIDProductKey*|*strstr*|*PRODUCT_SUBSTRING*)
      bad "is_target decides without reading the product string" ;;
    *)
      ok  "is_target decides without reading the product string" ;;
  esac
fi
src_lacks 'PRODUCT_SUBSTRING' ''                   "no product-name gate remains"

# doctor.sh must not keep its own copy of the product-id allow-list: a second copy is how
# the diagnostic came to disagree with the program about what a Magic Mouse is.
if grep -qE '0x0269|0x030[Dd]|"ProductID" = \(?[0-9]{3}' "$HERE/scripts/doctor.sh"; then
  bad "doctor.sh derives the product ids instead of hardcoding them"
else
  ok  "doctor.sh derives the product ids instead of hardcoding them"
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
