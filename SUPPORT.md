# Pulse Notch Support

Pulse Notch is currently an ad-hoc signed, non-notarized release for Apple Silicon Macs. It is not signed with an Apple Developer ID, distributed through the Mac App Store, or updated automatically.

For help or bug reports, use [GitHub Issues](https://github.com/rohangore1999/pulse-notch/issues).

## Supported setup

- Apple Silicon Mac (M1 or newer); Intel Macs are not supported
- macOS 13 Ventura or newer
- WHOOP 5.0 with **Heart Rate Broadcast** enabled

Pulse Notch reads the standard Bluetooth Heart Rate Service. It does not connect to your WHOOP account or the WHOOP cloud API.

## Installation help

Download the current installer from:

[https://github.com/rohangore1999/pulse-notch/releases/latest/download/PulseNotch.dmg](https://github.com/rohangore1999/pulse-notch/releases/latest/download/PulseNotch.dmg)

Open the DMG, drag Pulse Notch into Applications, eject the DMG, and try to open the installed app once. Because this release is not notarized, macOS will block that attempt. Open **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway** for Pulse Notch, and confirm the launch.

The option appears only after the blocked launch attempt and may be available for a limited time. On a work- or school-managed Mac, organizational policy may prevent **Open Anyway**; ask the administrator rather than attempting to bypass that policy.

## WHOOP does not appear or connect

1. In the WHOOP mobile app, open Device Settings and enable **Heart Rate Broadcast**.
2. Keep WHOOP snug on your wrist and close to the Mac.
3. In **System Settings → Privacy & Security → Bluetooth**, make sure Pulse Notch is allowed.
4. From the heart menu-bar item, choose **Scan for Monitor**.
5. Select your WHOOP explicitly from the results; Pulse Notch does not automatically approve an unknown nearby device.
6. If a previously approved device is wrong, open Pulse Notch settings, choose **Forget device**, and scan again.

Device discovery names are supplied by Bluetooth and can vary. Confirm the device using its displayed name and proximity before approving it.

## Notifications do not appear

Check both Pulse Notch settings and **System Settings → Notifications → Pulse Notch**. A reminder is sent only when live readings remain at or near your chosen threshold for the configured duration. Pulse Notch uses 5 BPM of hysteresis, so an active threshold excursion resets after the reading falls at least 5 BPM below the threshold. Presentation privacy suppresses the overlay and reminders while enabled.

Pulse Notch is not a medical or emergency alerting system.

## Updates and uninstalling

There is no automatic updater. Follow the manual [update](README.md#updates) and [uninstall](README.md#uninstall) instructions in the README.

## Reporting a bug

Before opening an issue, please include:

- Mac model and macOS version
- Pulse Notch version
- Whether Heart Rate Broadcast is enabled
- The connection status shown by Pulse Notch
- Reproduction steps and what you expected to happen

Do not post personally identifying health information, full Bluetooth identifiers, or screenshots containing unrelated private content. Logs are not uploaded automatically because Pulse Notch has no analytics or crash-reporting service.

## Compatibility and affiliation

Heart-rate zones, thresholds, colors, and coaching cues shown by Pulse Notch are app-defined and are not official WHOOP classifications. Pulse Notch is independently developed and is not affiliated with, endorsed by, or sponsored by WHOOP. WHOOP is a trademark of its respective owner.
