# magicmousefix

Your Magic Mouse pairs after the macOS 27 update, says *Connected*, shows its battery — and does
nothing. This sends it the one HID report macOS 27 forgot to send, and nothing else.

Derived from [`oleksandr-antonian/macos27-magic-mouse-fix`](https://github.com/oleksandr-antonian/macos27-magic-mouse-fix),
hardened to touch as little of your machine as possible. Every deviation is listed in
[`docs/upstream-diff.md`](docs/upstream-diff.md).

## The easy way — no Terminal needed

**Double-click `Comece-aqui.command` in Finder.** A guided assistant (in Portuguese) opens in a
Terminal window and walks through it one step at a time: it checks your Mac, builds the program,
runs the safety checks, finds your mouse *without touching it*, and only then asks whether you want
to apply the fix. Nothing happens until you answer yes, and you can stop by closing the window.

To remove everything later: double-click `Desinstalar.command`.

Guide in plain Portuguese: [`docs/GUIA-RAPIDO.md`](docs/GUIA-RAPIDO.md).

> macOS may refuse to open a `.command` file you downloaded from the internet. If that happens,
> right-click it and choose **Open** — that offers an "Open anyway" button the double-click does not.

The rest of this README is the manual route, for people who prefer the Terminal.

## Before you run it

It writes to hardware as root. That deserves a minute of your time, so:

- It is **one C file, ~450 lines**, with no dependencies. Read it: [`src/magicmousefix.c`](src/magicmousefix.c).
- It only ever opens devices matching `VendorID 0x05AC` and a listed Magic Mouse product id. Your keyboards are never opened, let alone written to.
- It reads no input, makes no network call, writes no file and spawns no process. `make test` asserts all four against the source rather than asking you to take it on faith.
- `--dry-run` shows you exactly what it would write to, and writes nothing.
- Everything the installer puts on your system is listed in [`scripts/install.sh`](scripts/install.sh) and removed by [`scripts/uninstall.sh`](scripts/uninstall.sh).

## Try it

```bash
make build          # clang, no dependencies
make test           # 21 checks, touches no hardware
./scripts/doctor.sh # what this Mac sees: OS, mouse, install state, daemon
```

Then look before you leap — this sends nothing:

```bash
sudo ./magicmousefix --dry-run
```

If it lists your mouse, apply the fix:

```bash
sudo ./magicmousefix
```

The mouse should wake up immediately. It stays fixed until it disconnects or the Mac sleeps.

## Make it stick

The daemon re-sends the report whenever the mouse reconnects, and survives reboot:

```bash
sudo ./scripts/install.sh
```

It installs `/usr/local/libexec/magicmousefix`, a LaunchDaemon, and a log-rotation rule — the script
lists them at the top. Check on it any time with `./scripts/doctor.sh`.

Still dying after sleep? Add `--heartbeat` and `60` to `ProgramArguments` in
[`launchd/com.local.magicmousefix.plist`](launchd/com.local.magicmousefix.plist) — **after**
`--agent`, keeping it — then re-run the installer. `--heartbeat` without `--agent` is refused with
exit code `2`, rather than silently doing nothing.

## Undo it

```bash
sudo ./scripts/uninstall.sh
```

Everything goes except the log, which it tells you how to remove. The mouse reverts to the macOS 27
behaviour on its next reconnect.

## Stack

- Language: C11, Apple clang, `-Wall -Wextra -Werror`
- Frameworks: IOKit (`IOHIDManager`) and CoreFoundation. No third-party dependency, no package manager.
- Daemon: launchd (`com.local.magicmousefix`), log rotation via newsyslog
- Verified on: macOS 27.0 (build 26A428), arm64, Magic Mouse `0x05AC:0x0269` firmware 8.6.0

## Prerequisites

Xcode command line tools (`xcode-select --install`). That is all.

## Commands

| Action | Command | Touches hardware? |
|---|---|---|
| build | `make build` | no |
| lint | `make lint` | no |
| test | `make test` | no |
| status | `./scripts/doctor.sh` | no |
| preview the targets | `sudo ./magicmousefix --dry-run` | no |
| apply until disconnect | `sudo ./magicmousefix` | **yes** |
| install the daemon | `sudo ./scripts/install.sh` | **yes** |
| remove everything | `sudo ./scripts/uninstall.sh` | no |
| install (deps) | `n-a` — nothing to install | — |

## Structure

```
Comece-aqui.command   guided assistant — double-click this if you are not sure
Desinstalar.command   removes everything, also by double-click
src/magicmousefix.c   the whole program
scripts/              install.sh · uninstall.sh · doctor.sh
launchd/              the LaunchDaemon and the log-rotation rule
tests/                run.sh — behavioural tests, no hardware touched
docs/                 upstream-diff.md · GUIA-RAPIDO.md
```

## Please tell Apple too

This is a workaround, not a fix. Report it at [Apple Feedback](https://www.apple.com/feedback/macos.html)
with your firmware version:

```bash
system_profiler SPBluetoothDataType | grep -A 20 "Magic Mouse"
```

## Contributing

- Branches `feat/<name>` / `fix/<name>`; commits `type(scope): subject`, in English.
- Before opening a PR: `make lint && make test`. Both must be clean — the build is `-Werror`.
- The safety properties in "Before you run it" are not negotiable: the device allow-list, the two
  gates, the absence of input reading / network / file writes, and a `--dry-run` that cannot reach
  the send path. `tests/run.sh` asserts them; a change that needs those tests relaxed needs a much
  better reason than convenience.
- The report payload `F1 06 01 37` is a device contract taken from upstream. Changing it is not a
  refactor.

## Credit and license

The `F1 06 01 37` trick was first posted in [`o0mohd0o/MagicMouseFix`](https://github.com/o0mohd0o/MagicMouseFix);
the implementation this one derives from is [`oleksandr-antonian/macos27-magic-mouse-fix`](https://github.com/oleksandr-antonian/macos27-magic-mouse-fix).
MIT — see [`LICENSE`](LICENSE).
