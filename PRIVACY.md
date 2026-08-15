# Pulse Notch Privacy Policy

Effective: August 15, 2026

Pulse Notch is designed to process heart-rate data locally on your Mac. It does not require a Pulse Notch or WHOOP account and contains no developer-operated backend, analytics, advertising, crash-reporting SDK, or cloud-history feature.

## Data the app processes

### Bluetooth discovery and device selection

Pulse Notch scans locally for devices advertising the standard Bluetooth Heart Rate Service. During a scan it may hold a nearby device's Bluetooth identifier, displayed name, and signal strength in memory. After you explicitly select a device, Pulse Notch saves that device's identifier and displayed name in local app preferences so it can reconnect.

### Live heart-rate data

Pulse Notch receives Bluetooth Heart Rate Measurement data from the device you select. It processes BPM, sensor-contact status when provided, timestamps, and a locally derived zone to render the notch, chart, threshold state, and reset experience.

Raw live samples and the rolling chart history are held in memory, not written as a heart-rate history file or uploaded. While readings continue, the expanded chart retains at most approximately one hour of samples, capped at 36,000 readings. In-memory history is discarded when the app quits, when you forget the device, or when readings begin from a different device. A temporary reconnect to the same device can retain the existing in-memory window.

### Preferences

Pulse Notch stores the following on your Mac using macOS app preferences:

- Your selected device's Bluetooth identifier and displayed name
- Heart-rate threshold, sustained duration, zone configuration, and related cue settings
- Notification, sound, snooze, full-screen, presentation-privacy, and onboarding preferences

Choosing **Forget device** removes the approved device identifier and displayed name. Your other preferences remain until you change or reset them, or remove the app's local container as described in the [uninstall instructions](README.md#uninstall).

### Notifications

If you enable notifications, Pulse Notch submits a local notification to macOS after your configured threshold is sustained. Its text can include the current BPM and locally derived zone. macOS controls notification permission, display, sound, and Notification Center history. Pulse Notch does not maintain a separate notification log or send notification contents to the developer.

## Data collection, sharing, and network use

Pulse Notch itself does not transmit your Bluetooth identifiers, heart-rate readings, settings, or notification contents to the developer or to a third-party service. The current app has no account system, analytics, cloud sync, WHOOP cloud API integration, or automatic updater.

Downloading releases and opening GitHub links uses your browser and GitHub, which operate under their own privacy policies. Apple and macOS handle Bluetooth and notification permissions and may process system-level information according to your Apple and device settings.

## Permissions

- **Bluetooth:** Required to find the heart-rate monitor you select and receive its live Bluetooth broadcast.
- **Notifications:** Optional. Used only for the threshold reminders you enable.

Pulse Notch does not request access to Apple Health and does not sign in to or read data from your WHOOP account.

## Your controls

You can disable reminders in Pulse Notch or macOS settings, forget the approved Bluetooth device from Pulse Notch settings, quit the app to end live processing, and remove saved preferences by following the [uninstall instructions](README.md#uninstall).

## Wellness and WHOOP disclaimer

Pulse Notch is a user-configured wellness cue, not a medical device or emergency monitor. Its zones, thresholds, colors, and coaching cues are configured or calculated by Pulse Notch and are not official WHOOP classifications.

Pulse Notch is an independent project and is not affiliated with, endorsed by, or sponsored by WHOOP. WHOOP is a trademark of its respective owner.

## Changes and contact

Material changes to this policy will be published in this repository with an updated effective date. For privacy questions or reports, open a [GitHub Issue](https://github.com/rohangore1999/pulse-notch/issues).
