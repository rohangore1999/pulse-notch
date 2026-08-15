# Pulse Notch

Pulse Notch is a local macOS heart-rate threshold companion for WHOOP 5.0. It reads the standard Bluetooth Heart Rate Service directly from WHOOP Heart Rate Broadcast and presents live BPM in the drawable areas around the MacBook camera cutout.

The app has no login, analytics, developer-operated server, or cloud sync.

> [!WARNING]
> **Non-notarized release:** Pulse Notch is ad-hoc signed for packaging; it is not signed with an Apple Developer ID and is not notarized by Apple. macOS will block its first launch until you explicitly approve it in **System Settings → Privacy & Security → Open Anyway**. Install it only if you are comfortable using non-notarized software. A work- or school-managed Mac may prevent installation entirely.

## System requirements

- Apple Silicon Mac (M1 or newer); Intel Macs are not supported
- macOS 13 Ventura or newer
- WHOOP 5.0 with Heart Rate Broadcast enabled

## Download and install

[Download the latest PulseNotch.dmg](https://github.com/rohangore1999/pulse-notch/releases/latest/download/PulseNotch.dmg)

1. Open `PulseNotch.dmg`.
2. Drag **Pulse Notch** into the **Applications** shortcut in the installer window.
3. Eject the disk image, then try to open **Pulse Notch** from Applications.
4. After macOS blocks the first launch, open **System Settings → Privacy & Security**.
5. Scroll to **Security**, click **Open Anyway** for Pulse Notch, authenticate if asked, then confirm **Open**.
6. Allow Bluetooth access and follow setup to select your WHOOP explicitly.

The **Open Anyway** option appears only after a blocked launch attempt and may be available for a limited time. Organization-managed security policy can hide or disable it; contact your administrator rather than bypassing that policy.

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

The generated app is ad-hoc signed and not notarized. Verify it locally before packaging it into a release DMG.

## Connect WHOOP 5.0

1. Open the WHOOP mobile app.
2. Open Device Settings and enable **Heart Rate Broadcast**.
3. Launch Pulse Notch and allow Bluetooth access when macOS asks.
4. Follow the first-run setup, scan, and explicitly select your WHOOP.
5. Confirm the notch BPM updates continuously and closely follows the WHOOP app.

The heart menu-bar item also provides **Scan for Monitor** for quick reconnection.

## Important boundary

Pulse Notch is a user-configured wellness cue. It does not detect stress, diagnose a condition, provide emergency monitoring, or control the WHOOP device.

Heart-rate zones, thresholds, colors, and coaching cues shown by Pulse Notch are configured or calculated by Pulse Notch; they are not official WHOOP classifications. Pulse Notch is an independent project and is not affiliated with, endorsed by, or sponsored by WHOOP. WHOOP is a trademark of its respective owner.

## Privacy and support

- Read the [privacy policy](PRIVACY.md) for the exact local data and retention behavior.
- Report bugs or request help through [GitHub Issues](https://github.com/rohangore1999/pulse-notch/issues).

## Updates

Pulse Notch has no automatic updater. To update, quit Pulse Notch from its heart menu-bar item, download the latest DMG from the link above, and drag the new app into Applications, choosing **Replace** when Finder asks. Your preferences normally remain because the bundle identifier stays the same. macOS may require **Open Anyway** again for a newly downloaded release.

## Uninstall

1. Choose **Quit Pulse Notch** from the heart menu-bar item.
2. Move **Pulse Notch.app** from Applications to the Trash.
3. To also erase saved settings and the approved Bluetooth device, in Finder choose **Go → Go to Folder…**, enter `~/Library/Containers/com.rohangore.pulsenotch`, and move that Pulse Notch container to the Trash if it exists.
4. Clear any previous Pulse Notch notifications from macOS Notification Center separately if desired.

Deleting the app alone does not necessarily delete its local preferences.
