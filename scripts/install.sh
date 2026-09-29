#!/bin/bash
# install.sh — install magicmousefix as a system LaunchDaemon.
#
# Idempotent: re-running it re-installs cleanly over a previous install.
# Everything it touches is listed at the top, and uninstall.sh reverses all of it.
#
#   /usr/local/libexec/magicmousefix          the binary
#   /Library/LaunchDaemons/com.local.magicmousefix.plist
#   /etc/newsyslog.d/magicmousefix.conf       log rotation
#   /var/log/magicmousefix.log                the log (created by launchd)
set -euo pipefail

LABEL=com.local.magicmousefix
BIN_DST=/usr/local/libexec/magicmousefix
PLIST_DST=/Library/LaunchDaemons/$LABEL.plist
ROTATE_DST=/etc/newsyslog.d/magicmousefix.conf

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN_SRC=$HERE/magicmousefix
PLIST_SRC=$HERE/launchd/$LABEL.plist
ROTATE_SRC=$HERE/launchd/magicmousefix.newsyslog.conf

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run with sudo: sudo $0"
[ -f "$BIN_SRC" ]    || die "$BIN_SRC not found — run 'make build' first"
[ -f "$PLIST_SRC" ]  || die "$PLIST_SRC not found"
# Every source is checked up front, before anything is stopped or copied. Checking only
# some of them means a missing file aborts halfway: the old daemon booted out, the new one
# never bootstrapped, and the machine left worse than before the run.
[ -f "$ROTATE_SRC" ] || die "$ROTATE_SRC not found"

echo "==> verifying the binary before installing it"
# --dry-run sends nothing; it only proves the binary runs and can see the mouse.
if "$BIN_SRC" --dry-run; then
  :
else
  echo "    (no Magic Mouse matched right now — installing anyway; the agent waits for one)"
fi

echo "==> stopping any previous daemon"
launchctl bootout "system/$LABEL" 2>/dev/null || true

echo "==> installing files"
# `install -d` sets owner and mode even on a directory that already exists, so running it
# unconditionally would silently re-own shared directories this installer did not create
# (/usr/local/libexec is commonly Homebrew's and user-owned) — a change uninstall.sh
# cannot reverse, and one the header above does not declare. Only create what is missing.
ensure_dir() {
  [ -d "$1" ] || install -d -o root -g wheel -m 755 "$1"
}
ensure_dir "$(dirname "$BIN_DST")"
ensure_dir /etc/newsyslog.d

install -o root -g wheel -m 755 "$BIN_SRC"    "$BIN_DST"
install -o root -g wheel -m 644 "$PLIST_SRC"  "$PLIST_DST"
install -o root -g wheel -m 644 "$ROTATE_SRC" "$ROTATE_DST"

echo "==> loading the daemon"
# `bootstrap` returns 5 ("Input/output error") when the job is already loaded. The check
# below is what decides whether the install worked, so a non-zero here is not fatal.
launchctl bootstrap system "$PLIST_DST" || true
launchctl enable "system/$LABEL" 2>/dev/null || true

sleep 1
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
  echo "==> installed and running"
  echo "    state:     $(launchctl print "system/$LABEL" 2>/dev/null | awk '/^\tstate = /{print $3}')"
  echo "    log:       /var/log/magicmousefix.log"
  echo "    status:    ./scripts/doctor.sh"
  echo "    uninstall: sudo ./scripts/uninstall.sh"
else
  die "the daemon did not come up — check /var/log/magicmousefix.log"
fi
