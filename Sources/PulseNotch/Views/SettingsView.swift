import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: HeartRateAppModel

    @AppStorage("pulseNotch.onboardingComplete.v1") private var onboardingComplete = false
    @AppStorage("pulseNotch.alertSound.v1") private var alertSoundEnabled = true
    @AppStorage("pulseNotch.defaultSnoozeMinutes.v1") private var defaultSnoozeMinutes = 15
    @AppStorage(DisplayPreferenceKeys.compactInFullscreen) private var fullscreenCompactOnly = true
    @AppStorage(DisplayPreferenceKeys.hideInFullscreen) private var hideInFullscreen = false
    @AppStorage(DisplayPreferenceKeys.presentationPrivacy) private var presentationPrivacy = false

    @State private var notificationPermission: PulseNotificationPermission = .checking
    @State private var showsBroadcastHelp = false

    var body: some View {
        Group {
            if onboardingComplete && ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_ONBOARDING_STEP"] == nil {
                settingsContent
            } else {
                OnboardingFlowView(model: model) {
                    onboardingComplete = true
                    ensureThresholdMode()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 620)
        .background(FocusDotTheme.panel)
        .preferredColorScheme(.dark)
    }

    private var settingsContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    connectionSection
                    heartRateThresholdSection
                    notificationSection
                    displayAndPrivacySection
                        .id("display-and-privacy")
                    footer
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(24)
            }
            .background(FocusDotTheme.panel)
            .onAppear {
                ensureThresholdMode()
                PulseNotificationPermission.read { notificationPermission = $0 }
                if ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_SETTINGS_SECTION"] == "display" {
                    DispatchQueue.main.async {
                        proxy.scrollTo("display-and-privacy", anchor: .top)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            FocusDotMark(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Pulse Notch")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FocusDotTheme.textPrimary)
                Text("Heart rate cue settings")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusDotTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(model.connectionStatus.isLive && !model.isStale ? FocusDotTheme.live : FocusDotTheme.unavailable)
                    .frame(width: 7, height: 7)
                Text(model.connectionStatus.isLive && !model.isStale ? "LIVE" : "OFFLINE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(FocusDotTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(FocusDotTheme.raised, in: Capsule())
            .overlay { Capsule().stroke(FocusDotTheme.border, lineWidth: 1) }
        }
    }

    private var connectionSection: some View {
        SettingsSection(title: "WHOOP connection", detail: "Live Bluetooth signal") {
            VStack(alignment: .leading, spacing: 12) {
                ConnectionResilienceCard(model: model, showsDeviceResults: true)

                if model.approvedDeviceID != nil {
                    approvedDeviceRow
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.focusDotContentOpen) {
                            showsBroadcastHelp.toggle()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Label("How to enable WHOOP broadcast", systemImage: "questionmark.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(showsBroadcastHelp ? 90 : 0))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FocusDotTheme.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .accessibilityLabel("How to enable WHOOP broadcast")
                    .accessibilityValue(showsBroadcastHelp ? "Expanded" : "Collapsed")

                    if showsBroadcastHelp {
                        VStack(alignment: .leading, spacing: 8) {
                            NumberedHelpRow(number: 1, text: "Open the WHOOP app and tap the device indicator at the top right.")
                            NumberedHelpRow(number: 2, text: "Open Device Settings, then find Status.")
                            NumberedHelpRow(number: 3, text: "Turn on Heart Rate Broadcast and return here.")
                        }
                        .padding(.top, 3)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var approvedDeviceRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FocusDotTheme.live)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.approvedDeviceName ?? "Approved heart-rate device")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FocusDotTheme.textPrimary)
                Text("Approved for automatic reconnect")
                    .font(.system(size: 9))
                    .foregroundStyle(FocusDotTheme.textTertiary)
            }

            Spacer(minLength: 12)

            Button("Forget device") {
                model.forgetApprovedDevice()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(FocusDotTheme.elevated)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                FocusDotTheme.elevated.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FocusDotTheme.elevated.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .pointingHandCursor()
            .accessibilityLabel("Forget \(model.approvedDeviceName ?? "approved heart-rate device")")
            .accessibilityHint("Stops automatic reconnect and returns to device scanning.")
        }
        .padding(.horizontal, 4)
    }

    private var heartRateThresholdSection: some View {
        SettingsSection(title: "Heart Rate Threshold", detail: "Your personal attention cue") {
            VStack(alignment: .leading, spacing: 12) {
                FocusDotCard {
                    VStack(alignment: .leading, spacing: 17) {
                        LabeledBPMControl(
                            title: "Alert above",
                            detail: "Not a workout zone or medical limit.",
                            value: heartRateThresholdBinding
                        )

                        Divider().overlay(FocusDotTheme.border)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Only after it stays elevated")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(FocusDotTheme.textPrimary)
                                Spacer()
                                Text("\(Int(model.settings.alerts.dwellSeconds)) sec")
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(FocusDotTheme.liveHighlight)
                            }
                            Slider(value: dwellBinding, in: 15...120, step: 5)
                                .tint(FocusDotTheme.live)
                                .pointingHandCursor()
                        }
                    }
                }
            }
        }
    }

    private var notificationSection: some View {
        SettingsSection(title: "Notifications", detail: "Optional and restrained") {
            VStack(alignment: .leading, spacing: 12) {
                NotificationPermissionCard(
                    model: model,
                    permission: $notificationPermission,
                    soundEnabled: $alertSoundEnabled
                )

                FocusDotCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Default snooze")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FocusDotTheme.textPrimary)
                            Text("Used when you pause reminders from an elevated state.")
                                .font(.system(size: 10))
                                .foregroundStyle(FocusDotTheme.textTertiary)
                        }
                        Spacer()
                        Picker("Default snooze", selection: $defaultSnoozeMinutes) {
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                        .labelsHidden()
                        .frame(width: 104)
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    private var displayAndPrivacySection: some View {
        SettingsSection(title: "Display & privacy", detail: "Quiet during focused work") {
            FocusDotCard {
                VStack(alignment: .leading, spacing: 15) {
                    PreferenceToggle(
                        title: "Hide when an app fills the screen",
                        detail: "Hide Pulse Notch when the active app uses a macOS full-screen Space or a maximized window. Monitoring and notifications continue.",
                        isOn: $hideInFullscreen
                    )

                    Divider().overlay(FocusDotTheme.border)

                    PreferenceToggle(
                        title: "Compact in full screen",
                        detail: "When visible, close expanded details automatically and keep the compact notch view.",
                        isOn: $fullscreenCompactOnly
                    )
                    .disabled(hideInFullscreen)
                    .opacity(hideInFullscreen ? 0.48 : 1)

                    Divider().overlay(FocusDotTheme.border)

                    PreferenceToggle(
                        title: "Presentation privacy",
                        detail: "Hide the overlay and mute coach alerts while privacy mode is active; monitoring can continue locally.",
                        isOn: $presentationPrivacy
                    )

                    Divider().overlay(FocusDotTheme.border)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(FocusDotTheme.liveHighlight)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Local by design")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FocusDotTheme.textPrimary)
                            Text("Live readings and preferences stay on this Mac. Pulse Notch has no WHOOP login, server, analytics, or cloud history.")
                                .font(.system(size: 10))
                                .foregroundStyle(FocusDotTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Run setup again") {
                onboardingComplete = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(FocusDotTheme.liveHighlight)
            .pointingHandCursor()

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var heartRateThresholdBinding: Binding<Int> {
        Binding(
            get: { model.settings.alerts.bpmThreshold },
            set: { value in
                var alerts = model.settings.alerts
                alerts.mode = .bpm
                alerts.bpmThreshold = min(220, max(40, value))
                model.settings.alerts = alerts
            }
        )
    }

    private var dwellBinding: Binding<Double> {
        Binding(
            get: { model.settings.alerts.dwellSeconds },
            set: { value in
                var alerts = model.settings.alerts
                alerts.mode = .bpm
                alerts.dwellSeconds = value
                model.settings.alerts = alerts
            }
        )
    }

    private func ensureThresholdMode() {
        var alerts = model.settings.alerts
        guard alerts.mode != .bpm else { return }
        alerts.mode = .bpm
        model.settings.alerts = alerts
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FocusDotTheme.textPrimary)
                Spacer()
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(FocusDotTheme.textTertiary)
            }
            content
        }
    }
}

private struct NumberedHelpRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 18, height: 18)
                .background(FocusDotTheme.live, in: Circle())
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(FocusDotTheme.textSecondary)
                .padding(.top, 2)
        }
    }
}

private struct PreferenceToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FocusDotTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(FocusDotTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(FocusDotTheme.live)
                .pointingHandCursor()
        }
    }
}
