// magicmousefix.c — re-enables multi-touch mode on an Apple Magic Mouse under macOS 27.
//
// The bug: on macOS 27 the Apple multi-touch mouse driver never sends the feature report
// that switches the mouse out of boot-mouse mode into multi-touch mode. The mouse pairs,
// connects and reports its battery level, but delivers no motion, clicks or gestures.
//
// This program sends that one report on the driver's behalf. It reads no input, writes no
// files and makes no network calls.
//
// Derived from https://github.com/oleksandr-antonian/macos27-magic-mouse-fix (MIT), which
// is the source of truth for the report bytes and for the LaunchDaemon shape. The report
// itself originates in the Linux hid-magicmouse driver, by way of o0mohd0o/MagicMouseFix.
//
// What this version changes, and why:
//
//   1. It matches ONLY Apple Magic Mouse vendor/product IDs. The upstream passes NULL to
//      IOHIDManagerSetDeviceMatching, which opens EVERY HID device on the machine — the
//      internal keyboard, any Magic Keyboard, every USB receiver. That is the whole Input
//      Monitoring surface held open for the life of a root daemon, to talk to one mouse.
//      Here the manager never opens a device that is not on the allow-list.
//   2. The allow-list is checked twice before a single byte is written: in the matching
//      dictionary, and again on the device itself. Identity is the vendor id and product
//      id only — never the product string, which on this device is the owner's editable
//      Bluetooth name (see is_target).
//   3. --dry-run enumerates and reports without sending anything. Run it first.
//   4. The burst stops as soon as the mouse accepts the report, instead of writing to the
//      device a fixed six times regardless.
//   5. --heartbeat is validated and floored, so an edited plist cannot hammer the device.
//   6. Logging is de-duplicated, so a resident daemon does not grow /var/log without bound.
//
// Build:
//   clang -O2 -Wall -Wextra -o magicmousefix src/magicmousefix.c \
//         -framework IOKit -framework CoreFoundation
//
// Modes:
//   magicmousefix --dry-run          list matching interfaces, send nothing
//   magicmousefix                    send the report once and exit
//   magicmousefix --agent            stay resident, re-send whenever a Magic Mouse appears
//   magicmousefix --agent --heartbeat 60
//                                    same, plus a repeat every 60 s (only needed if the
//                                    mouse goes silent again after sleep)
//
// Exit codes: 0 ok · 1 nothing accepted the report · 2 bad usage · 3 no HID access.
//
// SPDX-License-Identifier: MIT

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <errno.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// ---------------------------------------------------------------------------
// The report. Byte 0 is the report ID; the remaining three are the payload.
// ---------------------------------------------------------------------------
static const uint8_t kEnableMultitouch[] = { 0xF1, 0x06, 0x01, 0x37 };

// ---------------------------------------------------------------------------
// Device allow-list. Nothing outside it is ever opened, let alone written to.
//
// Every id here has a checkable source. An earlier version also carried 0x0323, written
// from memory as a Magic Mouse variant; it appears in no source consulted since, and has
// been removed. If you need it, --pid 0x0323 adds it deliberately.
//
//   0x0269  Magic Mouse 2. Observed directly on the reference machine
//           (macOS 27.0 build 26A428, product id 0x0269, firmware 1.9.2).
//   0x030D  Magic Mouse. Apple's own driver classifies it as a mouse:
//           /System/Library/Extensions/AppleBluetoothMultitouch.kext/Contents/Info.plist
//           lists ProductID 781 (0x030D) under the personality BNBMouseEventDriver.
//   0x0310  Magic Mouse (2011). Same plist, personality "BNBMouseEventDriver 2011".
//
// Deliberately NOT here: 0x030E, which the same plist lists under
// BNBTrackpadEventDriver. It is a Magic Trackpad, not a mouse.
//
// Extend at runtime with --pid 0xNNNN rather than widening the default.
// ---------------------------------------------------------------------------
// Apple identifies itself with two different numbers, and which one a Magic Mouse reports
// depends on how it is attached. 0x05AC is Apple's USB-IF vendor id; 0x004C is Apple's
// Bluetooth SIG company id, and that is what the HID layer reports for a mouse connected
// over Bluetooth — the normal case for this device. Matching only 0x05AC silently fails to
// find the mouse it was written for.
#define APPLE_VENDOR_ID_USB 0x05AC
#define APPLE_VENDOR_ID_BT  0x004C

static const int32_t kAppleVendorIds[] = { APPLE_VENDOR_ID_USB, APPLE_VENDOR_ID_BT };
#define APPLE_VENDOR_COUNT (sizeof(kAppleVendorIds) / sizeof(kAppleVendorIds[0]))

#define MAX_PIDS        16

static int32_t g_pids[MAX_PIDS] = { 0x0269, 0x030D, 0x0310 };
static size_t  g_pid_count      = 3;

// Shown when a device reports no product string at all. Nothing is ever decided from the
// product string — see is_target.
#define UNNAMED_DEVICE "(unnamed device)"

// The driver is still settling when the device shows up, so retry a few times — but stop
// as soon as the mouse answers, rather than writing a fixed number of times.
#define BURST_MAX_TRIES    6
#define BURST_INTERVAL     1.5
#define BURST_CONFIRMATION 2     // successful sends after which the burst stops

#define HEARTBEAT_MIN 5.0
#define HEARTBEAT_MAX 86400.0

#define LOG_REPEAT_SECS 3600     // re-state an unchanged situation at most once an hour

// The HID manager is never held in a global: it is created once in main and threaded
// through as an argument and as the callback/timer context. A mutable global handle is
// what forces every caller to re-check it for NULL, and what stops the clang analyzer
// proving the nullability of any of these calls.
static CFRunLoopTimerRef g_burst_timer = NULL;
static int               g_tries_left  = 0;
static int               g_confirmed   = 0;
static int               g_dry_run     = 0;
static int               g_verbose     = 0;

// ---------------------------------------------------------------------------
// Logging — de-duplicated. An unchanged line is suppressed until it either changes or
// LOG_REPEAT_SECS have passed, so a heartbeat daemon writes a handful of lines a day.
// ---------------------------------------------------------------------------
static char   g_last_line[256] = "";
static time_t g_last_time      = 0;

static void emit(const char *line) {
    char   stamp[32];
    time_t now = time(NULL);
    struct tm tm_now;
    localtime_r(&now, &tm_now);
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tm_now);
    printf("%s %s\n", stamp, line);
    fflush(stdout);
    g_last_time = now;
    snprintf(g_last_line, sizeof(g_last_line), "%s", line);
}

static void log_line(const char *fmt, ...) {
    char line[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    emit(line);
}

// Same as log_line, but silent while the message is identical to the last one and less
// than LOG_REPEAT_SECS old.
static void log_state(const char *fmt, ...) {
    char line[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);

    if (!g_verbose && strcmp(line, g_last_line) == 0 &&
        difftime(time(NULL), g_last_time) < LOG_REPEAT_SECS)
        return;
    emit(line);
}

// ---------------------------------------------------------------------------
// Device inspection
// ---------------------------------------------------------------------------
static int int_prop(IOHIDDeviceRef dev, CFStringRef key, int32_t *out) {
    CFTypeRef p = IOHIDDeviceGetProperty(dev, key);
    if (!p || CFGetTypeID(p) != CFNumberGetTypeID()) return 0;
    return CFNumberGetValue((CFNumberRef)p, kCFNumberSInt32Type, out) ? 1 : 0;
}

static int str_prop(IOHIDDeviceRef dev, CFStringRef key, char *buf, size_t len) {
    buf[0] = '\0';
    CFTypeRef p = IOHIDDeviceGetProperty(dev, key);
    if (!p || CFGetTypeID(p) != CFStringGetTypeID()) return 0;
    return CFStringGetCString((CFStringRef)p, buf, (CFIndex)len, kCFStringEncodingUTF8) ? 1 : 0;
}

static int pid_allowed(int32_t pid) {
    for (size_t i = 0; i < g_pid_count; i++)
        if (g_pids[i] == pid) return 1;
    return 0;
}

static int vendor_allowed(int32_t vid) {
    for (size_t i = 0; i < APPLE_VENDOR_COUNT; i++)
        if (kAppleVendorIds[i] == vid) return 1;
    return 0;
}

// The device's identity is its vendor id and product id. Those are burned into the
// hardware; they are what "this is a Magic Mouse" actually means, and they are the same
// on every Mac in the world.
//
// The product STRING is not identity. On this device it is the owner's Bluetooth name —
// "Magic Mouse de Arlindo" on the machine this was developed against, and just as legally
// "Mouse do escritório", "Magic Mouse 2", or the same words in another language. An
// earlier version of this program required that string to contain "Magic Mouse" and
// called it a second gate. It was not a gate: a device spoofing Apple's vendor id and a
// Magic Mouse product id would spoof the name too, so it stopped nothing — while silently
// refusing to fix any mouse whose owner had renamed it. It is reported, never required.
//
// What survives is the check being made TWICE: once in the matching dictionary, which is
// what keeps the manager from opening anything else, and again here on the device itself,
// so an error in building that dictionary still cannot turn into a write to other
// hardware.
static int is_target(IOHIDDeviceRef dev) {
    int32_t vid = 0, pid = 0;
    if (!int_prop(dev, CFSTR(kIOHIDVendorIDKey), &vid)) return 0;
    if (!int_prop(dev, CFSTR(kIOHIDProductIDKey), &pid)) return 0;
    return vendor_allowed(vid) && pid_allowed(pid);
}

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------

// Sends the report to every allowed interface currently present.
// Returns the number of interfaces that accepted it; -1 if the device set is unreadable.
static int send_to_all(IOHIDManagerRef mgr) {
    // With nothing matching the allow-list, IOHIDManagerCopyDevices returns NULL rather
    // than an empty set — so "no mouse attached" arrives here as a null pointer, not as
    // count == 0. Treating that as an error made the common case exit silently.
    CFSetRef devices = IOHIDManagerCopyDevices(mgr);
    CFIndex  count   = devices ? CFSetGetCount(devices) : 0;

    if (count <= 0) {
        if (devices) CFRelease(devices);
        // A dry run still owes the caller its summary line: "nothing was sent" is the one
        // reassurance the mode exists to give, and it must not depend on a mouse being
        // awake at the time.
        if (g_dry_run) {
            log_line("dry run: 0 Magic Mouse interface(s) matched, nothing sent");
            return 0;
        }
        log_state("no Magic Mouse interface present");
        return 0;
    }

    IOHIDDeviceRef *list = calloc((size_t)count, sizeof(IOHIDDeviceRef));
    if (!list) {
        CFRelease(devices);
        return -1;
    }
    CFSetGetValues(devices, (const void **)list);

    int found = 0, sent = 0;
    for (CFIndex i = 0; i < count; i++) {
        if (!is_target(list[i])) continue;
        found++;

        if (g_dry_run) {
            int32_t vid = 0, pid = 0;
            char    name[256];
            int_prop(list[i], CFSTR(kIOHIDVendorIDKey), &vid);
            int_prop(list[i], CFSTR(kIOHIDProductIDKey), &pid);
            // Purely for the operator to recognise the device. A mouse with no product
            // string is still a valid target — the ids are what decided it.
            if (!str_prop(list[i], CFSTR(kIOHIDProductKey), name, sizeof(name)))
                snprintf(name, sizeof(name), "%s", UNNAMED_DEVICE);
            log_line("would send F1 06 01 37 to \"%s\" (vid 0x%04X pid 0x%04X)",
                     name, (unsigned)vid, (unsigned)pid);
            continue;
        }

        IOReturn r = IOHIDDeviceSetReport(list[i],
                                          kIOHIDReportTypeFeature,
                                          kEnableMultitouch[0],
                                          kEnableMultitouch,
                                          (CFIndex)sizeof(kEnableMultitouch));
        if (r == kIOReturnSuccess) sent++;
        else if (g_verbose) log_line("interface refused the report: 0x%08x", r);
    }

    free(list);
    CFRelease(devices);

    if (g_dry_run) {
        log_line("dry run: %d Magic Mouse interface(s) matched, nothing sent", found);
        return found;
    }
    if (found) log_state("Magic Mouse: %d interface(s), %d accepted the report", found, sent);
    else       log_state("no Magic Mouse interface present");
    return sent;
}

// ---------------------------------------------------------------------------
// Burst — retry while the driver settles, and stop once the mouse answers.
// ---------------------------------------------------------------------------
static void stop_burst(void) {
    if (!g_burst_timer) return;
    CFRunLoopTimerInvalidate(g_burst_timer);
    CFRelease(g_burst_timer);
    g_burst_timer = NULL;
}

static void burst_tick(CFRunLoopTimerRef timer, void *info) {
    (void)timer;
    IOHIDManagerRef mgr = (IOHIDManagerRef)info;
    if (!mgr) return;
    if (send_to_all(mgr) > 0) g_confirmed++;
    if (--g_tries_left <= 0 || g_confirmed >= BURST_CONFIRMATION) stop_burst();
}

static void start_burst(IOHIDManagerRef mgr) {
    // A Magic Mouse presents several HID interfaces, so the device-matched callback fires
    // once per interface within a second or two of a reconnect. Later arrivals must only
    // EXTEND the burst already running, never restart it: send_to_all already writes to
    // every matching interface, so re-sending per arrival multiplies the writes for no
    // gain, and resetting g_confirmed each time can rearm the confirmation target
    // indefinitely, so the burst would stop only when the retries run out.
    if (g_burst_timer) {
        g_tries_left = BURST_MAX_TRIES - 1;
        return;
    }

    g_confirmed  = (send_to_all(mgr) > 0) ? 1 : 0;
    g_tries_left = BURST_MAX_TRIES - 1;

    if (g_confirmed >= BURST_CONFIRMATION) return;

    CFRunLoopTimerContext ctx = { 0, (void *)mgr, NULL, NULL, NULL };
    g_burst_timer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                         CFAbsoluteTimeGetCurrent() + BURST_INTERVAL,
                                         BURST_INTERVAL, 0, 0,
                                         burst_tick, &ctx);
    if (!g_burst_timer) return;
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), g_burst_timer, kCFRunLoopDefaultMode);
}

static void on_device_matched(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev) {
    (void)sender;
    IOHIDManagerRef mgr = (IOHIDManagerRef)ctx;
    if (!mgr || res != kIOReturnSuccess || !is_target(dev)) return;
    log_line("Magic Mouse appeared — sending report");
    start_burst(mgr);
}

static void heartbeat_tick(CFRunLoopTimerRef timer, void *info) {
    (void)timer;
    IOHIDManagerRef mgr = (IOHIDManagerRef)info;
    if (mgr) send_to_all(mgr);
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------
static CFDictionaryRef make_match(int32_t vid, int32_t pid) {
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(kCFAllocatorDefault, 2,
                                                         &kCFTypeDictionaryKeyCallBacks,
                                                         &kCFTypeDictionaryValueCallBacks);
    if (!d) return NULL;

    CFNumberRef v = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &vid);
    CFNumberRef p = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pid);
    if (v) { CFDictionarySetValue(d, CFSTR(kIOHIDVendorIDKey), v);  CFRelease(v); }
    if (p) { CFDictionarySetValue(d, CFSTR(kIOHIDProductIDKey), p); CFRelease(p); }
    return d;
}

// Restricts the manager to the allow-list. This is the difference that keeps a root daemon
// from holding every keyboard on the machine open.
static int apply_matching(IOHIDManagerRef mgr) {
    CFMutableArrayRef all = CFArrayCreateMutable(
        kCFAllocatorDefault, (CFIndex)(g_pid_count * APPLE_VENDOR_COUNT),
        &kCFTypeArrayCallBacks);
    if (!all) return 0;

    // One entry per (vendor id, product id) pair: the same mouse reports a different
    // vendor id over Bluetooth than over USB.
    for (size_t v = 0; v < APPLE_VENDOR_COUNT; v++) {
        for (size_t i = 0; i < g_pid_count; i++) {
            CFDictionaryRef m = make_match(kAppleVendorIds[v], g_pids[i]);
            if (!m) continue;
            CFArrayAppendValue(all, m);
            CFRelease(m);
        }
    }

    if (CFArrayGetCount(all) == 0) { CFRelease(all); return 0; }
    IOHIDManagerSetDeviceMatchingMultiple(mgr, all);
    CFRelease(all);
    return 1;
}

// Returns an open manager restricted to the allow-list, or NULL. The caller owns it.
static IOHIDManagerRef open_manager(void) {
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!mgr) {
        fprintf(stderr, "IOHIDManagerCreate failed\n");
        return NULL;
    }
    if (!apply_matching(mgr)) {
        fprintf(stderr, "could not build the device allow-list\n");
        CFRelease(mgr);
        return NULL;
    }

    IOReturn opened = IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
    if (opened != kIOReturnSuccess) {
        fprintf(stderr,
                "IOHIDManagerOpen failed: 0x%08x\n"
                "No HID access. Run with sudo, or grant your terminal the Input Monitoring\n"
                "permission in System Settings > Privacy & Security.\n",
                opened);
        CFRelease(mgr);
        return NULL;
    }
    return mgr;
}

static void usage(const char *argv0) {
    fprintf(stderr,
            "usage: %s [--dry-run] [--agent] [--heartbeat SECONDS] [--pid 0xNNNN] [--verbose]\n"
            "\n"
            "  --dry-run            list matching Magic Mouse interfaces; send nothing\n"
            "  --agent              stay resident and re-send on every reconnect\n"
            "  --heartbeat SECONDS  with --agent, also repeat every SECONDS (%.0f-%.0f)\n"
            "  --pid 0xNNNN         add one Apple product id to the allow-list\n"
            "  --verbose            log every attempt, including refusals\n",
            argv0, HEARTBEAT_MIN, HEARTBEAT_MAX);
}

static int parse_heartbeat(const char *s, double *out) {
    char  *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (errno || !end || *end != '\0' || !isfinite(v)) return 0;
    if (v < HEARTBEAT_MIN || v > HEARTBEAT_MAX) return 0;
    *out = v;
    return 1;
}

// 1 accepted · 0 not a usable product id · -1 the allow-list is full.
// The two failures need different messages: calling a perfectly valid id malformed
// because the list is full tells the user to fix the wrong thing.
#define PID_OK   1
#define PID_BAD  0
#define PID_FULL (-1)

static int parse_pid(const char *s) {
    char  *end = NULL;
    errno = 0;
    long v = strtol(s, &end, 0);
    if (errno || !end || *end != '\0' || v <= 0 || v > 0xFFFF) return PID_BAD;
    if (pid_allowed((int32_t)v)) return PID_OK;  // already there — not an error
    if (g_pid_count >= MAX_PIDS) return PID_FULL;
    g_pids[g_pid_count++] = (int32_t)v;
    return PID_OK;
}

int main(int argc, char **argv) {
    int    agent     = 0;
    double heartbeat = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--agent") == 0) {
            agent = 1;
        } else if (strcmp(argv[i], "--dry-run") == 0) {
            g_dry_run = 1;
        } else if (strcmp(argv[i], "--verbose") == 0) {
            g_verbose = 1;
        } else if (strcmp(argv[i], "--heartbeat") == 0 && i + 1 < argc) {
            if (!parse_heartbeat(argv[++i], &heartbeat)) {
                fprintf(stderr, "--heartbeat: expected %.0f-%.0f seconds, got \"%s\"\n",
                        HEARTBEAT_MIN, HEARTBEAT_MAX, argv[i]);
                return 2;
            }
        } else if (strcmp(argv[i], "--pid") == 0 && i + 1 < argc) {
            int r = parse_pid(argv[++i]);
            if (r == PID_FULL) {
                fprintf(stderr, "--pid: the allow-list already holds %d product ids, "
                                "which is the maximum\n", MAX_PIDS);
                return 2;
            }
            if (r != PID_OK) {
                fprintf(stderr, "--pid: expected an Apple product id like 0x0269, got \"%s\"\n",
                        argv[i]);
                return 2;
            }
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    if (g_dry_run && agent) {
        fprintf(stderr, "--dry-run and --agent are mutually exclusive\n");
        return 2;
    }

    // Only the agent has a run loop to hang a heartbeat timer on. Accepting the flag
    // outside that mode and quietly doing nothing is the worst of both: in a LaunchDaemon
    // whose arguments lost --agent, the job would one-shot, exit, and be respawned by
    // KeepAlive every ThrottleInterval forever, still without the heartbeat that was asked
    // for. Refuse it here, where the message can name the cause.
    if (heartbeat > 0 && !agent) {
        fprintf(stderr, "--heartbeat only works together with --agent\n");
        return 2;
    }

    IOHIDManagerRef mgr = open_manager();
    if (!mgr) return 3;

    if (!agent) {
        int sent = send_to_all(mgr);
        IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
        CFRelease(mgr);
        if (g_dry_run) return sent > 0 ? 0 : 1;
        if (sent <= 0) {
            fprintf(stderr,
                    "No Magic Mouse interface accepted the report.\n"
                    "Run --dry-run to see whether the mouse is matched at all.\n");
            return 1;
        }
        return 0;
    }

    log_line("agent started (allow-list: %zu product id(s))", g_pid_count);

    IOHIDManagerRegisterDeviceMatchingCallback(mgr, on_device_matched, (void *)mgr);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    start_burst(mgr);                 // the mouse may already be connected

    if (heartbeat > 0) {
        CFRunLoopTimerContext hctx = { 0, (void *)mgr, NULL, NULL, NULL };
        CFRunLoopTimerRef hb = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                                    CFAbsoluteTimeGetCurrent() + heartbeat,
                                                    heartbeat, 0, 0,
                                                    heartbeat_tick, &hctx);
        if (hb) {
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), hb, kCFRunLoopDefaultMode);
            CFRelease(hb);            // the run loop retains it
            log_line("heartbeat every %.0f s", heartbeat);
        }
    }

    CFRunLoopRun();                   // does not return
    return 0;
}
