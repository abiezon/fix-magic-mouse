#!/bin/bash
# doctor.sh — report the state of the machine, the mouse and the daemon.
# Read-only: it inspects and prints, and changes nothing. Safe to run without sudo.
#
# Note on `grep -q`: this script deliberately does NOT use it in a pipeline. `grep -q`
# exits the moment it matches, which hands the upstream command a SIGPIPE; under
# `pipefail` the pipeline then reports failure on the very input that matched. Count with
# `grep -c` (which drains its input) and test the number instead.
set -uo pipefail

HERE_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LABEL=com.local.magicmousefix
BIN=/usr/local/libexec/magicmousefix
PLIST=/Library/LaunchDaemons/$LABEL.plist
LOG=/var/log/magicmousefix.log

say() { printf '%s\n' "$*"; }
hdr() { printf '\n== %s ==\n' "$*"; }

hdr "System"
say "macOS      $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
say "Arch       $(uname -m)"

# The Magic Mouse product ids come from ONE place: the allow-list in the C source. They
# were briefly duplicated here (once in hex for system_profiler, once in decimal for
# ioreg), which is how this script came to disagree with the program about what a Magic
# Mouse is — the exact failure it exists to diagnose. Read them instead.
SRC=$HERE_ROOT/src/magicmousefix.c
pids_hex=""
pids_dec=""
if [ -r "$SRC" ]; then
  for id in $(sed -n 's/.*g_pids\[MAX_PIDS\][^=]*= *{ *\([^}]*\)}.*/\1/p' "$SRC" \
              | tr -d ' ' | tr ',' '\n' | grep -E '^0[xX][0-9A-Fa-f]+$'); do
    pids_hex="${pids_hex:+$pids_hex|}$(printf '0x%04X' "$id")"
    pids_dec="${pids_dec:+$pids_dec|}$(printf '%d' "$id")"
  done
fi
if [ -z "$pids_hex" ]; then
  say "  cannot read the product-id allow-list from $SRC —"
  say "  device checks below are skipped rather than guessed"
fi

hdr "Magic Mouse — Bluetooth"
# Located by PRODUCT ID, never by name. The device name here is the owner's editable
# Bluetooth name ("Magic Mouse de Arlindo" on the reference machine, anything at all
# elsewhere), so keying on it reports a perfectly healthy mouse as "not paired".
# A fixed -A window is wrong too: system_profiler groups devices under "Connected:" /
# "Not Connected:" headers, and a window wide enough to cover the fields also swallows
# whichever header comes next — printing "Not Connected:" under a connected mouse.
bt=$(system_profiler SPBluetoothDataType 2>/dev/null | awk '
  { ind = match($0, /[^ ]/) }
  /^ *(Not )?Connected:$/ { sec = $0; gsub(/^ *| *$|:$/, "", sec); next }
  /:[[:space:]]*$/ && ind > 0 {
      if (hit) { print "state: " (blksec ? blksec : "unknown"); print "name: " dev; printf "%s", buf }
      buf = ""; hit = 0; inblk = 1; devind = ind; blksec = sec
      dev = $0; gsub(/^ *| *$|:$/, "", dev); next
  }
  inblk && ind <= devind {
      if (hit) { print "state: " (blksec ? blksec : "unknown"); print "name: " dev; printf "%s", buf }
      buf = ""; hit = 0; inblk = 0
  }
  inblk {
      buf = buf $0 "\n"
      if (pids != "" && toupper($0) ~ "PRODUCT ID: (" toupper(pids) ")") hit = 1
  }
  END { if (hit) { print "state: " (blksec ? blksec : "unknown"); print "name: " dev; printf "%s", buf } }
' pids="$pids_hex")
if [ -n "$bt" ]; then
  printf '%s\n' "$bt" \
    | grep -iE 'state:|name:|product id|vendor id|firmware|battery' \
    | sed 's/^ */  /'
else
  say "  no Magic Mouse product id found in the Bluetooth device list"
fi

hdr "Magic Mouse — HID"
# Matched on PRODUCT ID, never on the product string: over Bluetooth that string is the
# owner's device name, so `"Product" = "Magic Mouse"` misses a mouse called anything else
# — including this machine's, which reports "Magic Mouse de Arlindo" and was therefore
# reported as absent while it was connected and working.
# Still not reporting an interface COUNT from ioreg: the registry interleaves each
# device's node with its child interface node, so counting here is a guess dressed as a
# fact. The authoritative count is whatever IOHIDManager matches, which --dry-run prints.
if [ -n "$pids_dec" ]; then
  hid_hits=$(ioreg -c IOHIDDevice -r -l 2>/dev/null | grep -cE "\"ProductID\" = ($pids_dec)")
else
  hid_hits=0
fi
if [ "${hid_hits:-0}" -gt 0 ]; then
  say "  present in the IO registry"
else
  say "  no HID interfaces registered — asleep, or the link is idle"
  say "  (click the mouse or toggle its power switch to wake it)"
fi

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for candidate in "$HERE/magicmousefix" "$BIN"; do
  [ -x "$candidate" ] || continue
  if [ "$(id -u)" -eq 0 ]; then
    say "  interfaces the fix would write to, per $candidate:"
    "$candidate" --dry-run 2>&1 | sed 's/^/    /'
  else
    say "  for the exact interface list: sudo $candidate --dry-run  (sends nothing)"
  fi
  break
done

hdr "Installation"
[ -x "$BIN"    ] && say "  binary   $BIN  ($(stat -f '%Sp %Su:%Sg' "$BIN"))" || say "  binary   not installed"
[ -f "$PLIST"  ] && say "  plist    $PLIST ($(stat -f '%Sp %Su:%Sg' "$PLIST"))" || say "  plist    not installed"

hdr "Daemon"
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
  # Anchor on a single tab: `launchctl print` indents the job's own keys with one tab and
  # nested sub-structures with more. `^\s*` would also match those, so the block would
  # report the job's `state = running` followed by nested `state = active` lines.
  launchctl print "system/$LABEL" 2>/dev/null \
    | grep -E '^\t(state|pid|last exit code|program) ' | sed 's/^[[:space:]]*/  /'
else
  say "  not loaded"
fi

hdr "Log (last 10 lines)"
if [ -r "$LOG" ]; then
  tail -n 10 "$LOG" | sed 's/^/  /'
else
  say "  $LOG not present or not readable (try: sudo $0)"
fi

printf '\n'
