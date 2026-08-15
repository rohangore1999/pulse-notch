## Pulse Notch beta

Pulse Notch displays live heart rate from a WHOOP 5.0 Heart Rate Broadcast in the drawable areas around a MacBook camera cutout. This beta is Apple Silicon only and requires macOS 13 Ventura or newer.

### Install

1. Download `PulseNotch.dmg` and open it.
2. Drag **Pulse Notch** into the **Applications** shortcut.
3. Try to open Pulse Notch from Applications once.
4. Because this beta is not notarized, macOS will block the first launch. Open **System Settings → Privacy & Security**, scroll to **Security**, choose **Open Anyway**, and confirm.
5. Allow Bluetooth access, enable Heart Rate Broadcast in the WHOOP app, and explicitly select your WHOOP in Pulse Notch setup.

The app is ad-hoc signed rather than signed with an Apple Developer ID. Apple has not reviewed or notarized this beta. Managed Macs can prevent the Open Anyway override.

### Included

- Live BPM, heart-rate zone and compact trend around the camera cutout
- User-defined sustained heart-rate threshold alerts
- Rolling one-hour chart with time-labeled minute-average hover values
- Explicit nearby-device selection and saved WHOOP reconnection
- Guided 60-second breathing reset, snooze and privacy controls

### Important boundaries

Pulse Notch is a wellness cue, not medical monitoring, diagnosis, emergency detection or treatment. It is an independent app and is not affiliated with, endorsed by or sponsored by WHOOP. WHOOP is a trademark of its respective owner.

There is no automatic updater in this beta. Download future versions from the Pulse Notch GitHub Releases page and replace the existing app in Applications.

- [Privacy](https://github.com/rohangore1999/pulse-notch/blob/main/PRIVACY.md)
- [Support](https://github.com/rohangore1999/pulse-notch/blob/main/SUPPORT.md)
