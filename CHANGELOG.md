# Changelog

All relevant changes to this repository are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adopts [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

Restores a Magic Mouse left inert by the macOS 27 update, by sending it the multi-touch enable
report the system driver stopped sending. Runs once, or as a LaunchDaemon that re-applies it on
every reconnect and survives reboot. It only ever opens Apple Magic Mouse devices on an explicit
allow-list, reads no input and writes no files; `--dry-run` shows what it would touch without
touching it, and a single uninstall command removes everything it installed.

For people who do not use a Terminal, a guided assistant opens with a double-click, explains
each step in plain Portuguese, and asks before anything reaches the mouse or the system.

### Changed

### Fixed

### Removed
