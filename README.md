# Pulse Notch

Pulse Notch is a local macOS heart-rate threshold companion for WHOOP 5.0. It reads the standard Bluetooth Heart Rate Service directly from WHOOP Heart Rate Broadcast and presents live BPM in the drawable areas around the MacBook camera cutout.

The prototype has no login, analytics, server, or cloud sync.

## System requirements

- Apple Silicon Mac (M1 or newer); Intel Macs are not supported
- macOS 13 Ventura or newer
- WHOOP 5.0 with Heart Rate Broadcast enabled

## What is implemented

- A true cutout-aware compact view: live BPM on the left, zone and 60-second trend on the right
- Adaptive Liquid Glass on macOS 26 with a material fallback and accessibility-safe opaque mode on older systems
- A single-pass, interruption-safe downward morph with fast staged chart/actions, plus a rolling one-hour minute-average trend, reset, snooze, and settings
- Blue normal state, blue pending dwell progress, amber confirmed elevation, and gray stale/disconnected states
- User-configured sustained threshold and snooze, plus hysteresis, restrained cooldown, and factual macOS notifications
- A guided 60-second inhale-4/exhale-6 reset and completion state
- First-run WHOOP Broadcast guidance, Bluetooth permission recovery, explicit device selection, and connection resilience
- Full-screen compact or automatic-hide behavior, presentation privacy, and no-notch/external-display fallback
- Standard BLE Heart Rate Service (`180D`) and Heart Rate Measurement (`2A37`) support
- Saved-device reconnect, wake recovery, exponential retry, stale-reading protection, and off-wrist/no-contact suppression

## Build and run

```bash
./scripts/run-local-app.sh
```

Or build without launching:

```bash
./scripts/build-local-app.sh
open "dist/Pulse Notch.app"
```

Run the local parser and threshold-state tests:

```bash
./scripts/test-local.sh
```

The generated app is ad-hoc signed and intended for local testing on this Mac.

## Connect WHOOP 5.0

1. Open the WHOOP mobile app.
2. Open Device Settings and enable **Heart Rate Broadcast**.
3. Launch Pulse Notch and allow Bluetooth access when macOS asks.
4. Follow the first-run setup, scan, and explicitly select your WHOOP.
5. Confirm the notch BPM updates continuously and closely follows the WHOOP app.

The heart menu-bar item also provides **Scan for Monitor** for quick reconnection.

## Important boundary

Pulse Notch is a user-configured wellness cue. It does not detect stress, diagnose a condition, provide emergency monitoring, or control the WHOOP device.
