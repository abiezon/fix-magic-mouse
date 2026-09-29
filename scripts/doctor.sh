#!/bin/bash
# doctor.sh — report the state of the machine, the mouse and the daemon.
# Read-only: it inspects and prints, and changes nothing. Safe to run without sudo.
#
# Note on `grep -q`: this script deliberately does NOT use it in a pipeline. `grep -q`
# exits the moment it matches, which hands the upstream command a SIGPIPE; under
# `pipefail` the pipeline then reports failure on the very input that matched. Count with
# `grep -c` (which drains its input) and test the number instead.
set -uo pipefail

LABEL=com.local.magicmousefix
BIN=/usr/local/libexec/magicmousefix
PLIST=/Library/LaunchDaemons/$LABEL.plist
LOG=/var/log/magicmousefix.log

say() { printf '%s\n' "$*"; }
hdr() { printf '\n== %s ==\n' "$*"; }

hdr "System"
say "macOS      $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
say "Arch       $(uname -m)"

hdr "Magic Mouse — Bluetooth"
bt_hits=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -ci 'magic mouse')
if [ "${bt_hits:-0}" -gt 0 ]; then
  system_profiler SPBluetoothDataType 2>/dev/null \
    | grep -i -A 10 'magic mouse' \
    | grep -iE 'magic mouse|product id|vendor id|firmware|battery|connected' \
    | sed 's/^ */  /'
else
  say "  not paired, or Bluetooth reported nothing"
fi

hdr "Magic Mouse — HID"
# Deliberately not reporting an interface count parsed out of ioreg: the registry
# interleaves each device's node with its child interface node, and the Magic Keyboard's
# nodes sit in the same tree, so any grep-and-count here is a guess dressed as a fact.
# The authoritative count is whatever IOHIDManager matches, which is what --dry-run prints.
hid_hits=$(ioreg -c IOHIDDevice -r -l 2>/dev/null | grep -c '"Product" = "Magic Mouse"')
if [ "${hid_hits:-0}" -gt 0 ]; then
  say "  present in the IO registry"
else
  say "  absent from the IO registry — the mouse is not connected"
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
