#!/bin/bash
# uninstall.sh — remove everything install.sh put on the system.
# Safe to run when nothing is installed: each step is a no-op then.
set -uo pipefail

LABEL=com.local.magicmousefix
BIN_DST=/usr/local/libexec/magicmousefix
PLIST_DST=/Library/LaunchDaemons/$LABEL.plist
ROTATE_DST=/etc/newsyslog.d/magicmousefix.conf
LOG=/var/log/magicmousefix.log

[ "$(id -u)" -eq 0 ] || { echo "error: run with sudo: sudo $0" >&2; exit 1; }

echo "==> stopping the daemon"
launchctl bootout "system/$LABEL" 2>/dev/null || true

echo "==> removing files"
for f in "$PLIST_DST" "$BIN_DST" "$ROTATE_DST"; do
  if [ -e "$f" ]; then rm -f "$f" && echo "    removed $f"; fi
done

if [ -e "$LOG" ]; then
  echo "    kept    $LOG  (remove it yourself if you want: sudo rm $LOG)"
fi

echo "==> done. The mouse reverts to the macOS 27 behaviour on its next reconnect."
