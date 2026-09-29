# Deviations from upstream

The source of truth is
[`oleksandr-antonian/macos27-magic-mouse-fix`](https://github.com/oleksandr-antonian/macos27-magic-mouse-fix)
(MIT), read at commit `b0269f2`. This file accounts for every difference, so the two can be compared
without diffing them line by line.

**Unchanged, deliberately:** the report payload `F1 06 01 37`, its report id `0xF1`, the
`kIOHIDReportTypeFeature` type, the `IOHIDManager` + `CFRunLoop` approach, the single-file structure,
the LaunchDaemon shape, and the MIT license. The payload is a device contract taken on upstream's
authority; changing it is out of scope here.

## Security and reach

| # | Upstream | Here | Why |
|---|---|---|---|
| 1 | `IOHIDManagerSetDeviceMatching(g_manager, NULL)` — matches **every** HID device, then filters by product name after the fact | `IOHIDManagerSetDeviceMatchingMultiple` with an explicit `VendorID 0x05AC` + product-id allow-list | `IOHIDManagerOpen` opens everything that matched. Upstream's root daemon therefore holds every keyboard on the machine open for its entire life, to talk to one mouse. The Operator's Mac has a Magic Keyboard in the same HID tree, so this is concrete, not theoretical. |
| 2 | One gate: product name contains `Magic Mouse` | Two independent gates: the allow-list **and** the product name, re-checked on the device itself | A name check alone would send a feature report to any device calling itself "Magic Mouse". Re-checking on the device means a mistake in the matching dictionary still cannot turn into a write to other hardware. |
| 3 | No way to inspect before acting | `--dry-run` enumerates and reports, and cannot reach the send path | Running a stranger's code as root against your hardware should have a step where you can look first. |
| 4 | Allow-list is implicit and unextendable | `--pid 0xNNNN` widens it explicitly at runtime | Narrowing the default costs coverage of an unlisted Magic Mouse variant. The escape hatch keeps that cost, but makes widening a deliberate act rather than the default posture. |

## Correctness and robustness

| # | Upstream | Here | Why |
|---|---|---|---|
| 5 | `heartbeat = atof(argv[++i])` | `strtod` with trailing-character rejection and a 5–86400 s bound | `atof` turns `"abc"` into `0.0` silently, which reads as "no heartbeat" rather than as an error. The floor also stops an edited plist from hammering the device. |
| 6 | `--pid` does not exist | `strtol` with the same validation | Same reason. |
| 7 | Burst always fires `BURST_COUNT` (5) times plus the initial send, regardless of outcome, and every per-interface match callback restarts it | Retries while the driver settles, stops after 2 successful sends or 6 attempts; a later interface arrival only extends the running burst instead of restarting it | Fewer writes to hardware for the same effect. A mouse presents several HID interfaces, so restarting per arrival both multiplies the writes and keeps rearming the stop condition. A mouse that never accepts still gets every attempt. |
| 8 | `calloc((size_t)count, …)` with no guard on `count == 0` | Early return when the device set is empty | `calloc(0, n)` may return `NULL`, which upstream treats identically to an allocation failure. Harmless, but it conflates "no mouse" with "out of memory". |
| 9 | The heartbeat `CFRunLoopTimerRef` is never released | `CFRelease` after `CFRunLoopAddTimer` retains it | A leak bounded by process lifetime, so not a bug in practice — but it is the kind of thing that stops being harmless when the code is edited later. |
| 10 | `g_manager` is a file-scope global | The manager is a local in `main`, threaded through as an argument and as the callback/timer context | Every opaque IOKit call invalidates what the clang analyzer can prove about a global, so `--analyze` warned on every use of it. With the manager threaded explicitly, `make lint` is clean and a future real warning will be visible. |
| 11 | Exit codes: `0`, `1`, `2` | `0` ok · `1` nothing accepted · `2` bad usage · `3` no HID access | `3` separates "you lack permission" from "the mouse did not answer". They need different responses, and the LaunchDaemon's restart behaviour depends on telling them apart. |

## Operations

| # | Upstream | Here | Why |
|---|---|---|---|
| 12 | `log_line` on every send, including every heartbeat tick | De-duplicated: an unchanged line is suppressed for an hour; `--verbose` restores the full output | With `--heartbeat 60` upstream writes 1440 lines a day to an unrotated file. |
| 13 | Nothing rotates `/var/log/magicmousefix.log` | `launchd/magicmousefix.newsyslog.conf`, installed to `/etc/newsyslog.d/` | Same reason, from the other side. |
| 14 | Plist has `KeepAlive` with no `ThrottleInterval` | `ThrottleInterval 30`, plus `ProcessType Background` | If the agent exits immediately — no HID access, say — `KeepAlive` respawns it in a tight loop and fills the log with the same failure. |
| 15 | Installs to `/usr/local/bin/magicmousefix` | `/usr/local/libexec/magicmousefix` | It is a daemon helper, not a user command; it does not belong on `PATH`. (ADR-003) |
| 16 | Install and uninstall are copy-paste blocks in the README | `scripts/install.sh` and `scripts/uninstall.sh` | Idempotent, root-checked, verifies the binary with `--dry-run` first, declares every path it touches, and handles the `bootstrap` "already loaded" case the README describes in prose, and creates a system directory only when it is missing so an existing one is never silently re-owned. |
| 17 | No status command | `scripts/doctor.sh` | Read-only. Answers "is it installed, is it running, does the machine even see the mouse" without changing anything. |

## Testing

| # | Upstream | Here | Why |
|---|---|---|---|
| 18 | No tests | `tests/run.sh` — 24 cases | Argument and exit-code behaviour, plus "source guarantees": greps over the comment-stripped source asserting no network call, no file write, no subprocess and no input callback. It turns the reach and no-side-effects claims from prose in a README into something that fails the build. |
| 19 | No lint target | `make lint` — `clang -fsyntax-only` plus the static analyzer; build is `-Wall -Wextra -Werror` | Upstream builds with `-Wall` only. |

## Things upstream is right about, and this repo keeps

- **Source, not a binary.** The whole security argument is that you can read it before you run it.
- **One file.** Splitting it up would make it tidier and less trustworthy.
- **Root over Input Monitoring.** Running as root avoids granting a terminal permanent input access.
- **Tell Apple.** This is a workaround. Upstream's `system_profiler` snippet for the feedback report is worth using.

## Attribution

The `F1 06 01 37` trick was first published in
[`o0mohd0o/MagicMouseFix`](https://github.com/o0mohd0o/MagicMouseFix); upstream credits it and so does
this repo. Both are MIT; the upstream copyright notice is preserved in `LICENSE`.
