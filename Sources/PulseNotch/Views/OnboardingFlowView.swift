import AppKit
import Combine
import SwiftUI
import UserNotifications

struct OnboardingFlowView: View {
    @ObservedObject var model: HeartRateAppModel
    let onComplete: () -> Void

    @State private var step: SetupStep = .welcome
    @State private var notificationPermission: PulseNotificationPermission = .checking
    @AppStorage("pulseNotch.alertSound.v1") private var alertSoundEnabled = true
    @AppStorage("pulseNotch.notificationsEnabled.v1") private var notificationsEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    stepContent
                }
                .frame(maxWidth: 540, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }

            footer
        }
        .frame(minWidth: 520, minHeight: 620)
        .background(FocusDotTheme.panel)
        .preferredColorScheme(.dark)
        .onAppear {
            if ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_ONBOARDING_STEP"] == "threshold" {
                step = .threshold
            }
            PulseNotificationPermission.read { notificationPermission = $0 }
        }
        .onChange(of: step) { newStep in
            if newStep == .device, !model.connectionStatus.isLive {
                model.startScanning()
            }
            if newStep == .notifications {
                PulseNotificationPermission.read { notificationPermission = $0 }
            }
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(SetupStep.allCases) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? FocusDotTheme.live : FocusDotTheme.raised)
                        .frame(width: item == step ? 22 : 7, height: 7)
                        .animation(.easeOut(duration: 0.2), value: step)
                }
            }

            Spacer()

            Text("SETUP \(step.rawValue + 1) OF \(SetupStep.allCases.count)")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(FocusDotTheme.textTertiary)
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(FocusDotTheme.notch.opacity(0.45))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FocusDotTheme.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .broadcast:
            broadcastStep
        case .bluetooth:
            bluetoothStep
        case .device:
            deviceStep
        case .threshold:
            thresholdStep
        case .notifications:
            notificationsStep
        case .ready:
            readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            FocusDotMark(size: 58)

            SetupTitle(
                eyebrow: "WELCOME TO PULSE NOTCH",
                title: "A quieter way to notice your pace",
                detail: "See live heart rate at the notch and get one calm reminder when it stays above the heart rate threshold you choose."
            )

            FocusDotCard {
                VStack(alignment: .leading, spacing: 15) {
                    SetupBenefitRow(
                        icon: "waveform.path.ecg",
                        title: "Live from your WHOOP",
                        detail: "Reads the Bluetooth heart-rate broadcast directly."
                    )
                    SetupBenefitRow(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Your threshold, not a diagnosis",
                        detail: "A personal attention cue—not stress or medical monitoring."
                    )
                    SetupBenefitRow(
                        icon: "lock.shield.fill",
                        title: "Local and private",
                        detail: "No WHOOP login, cloud account, analytics, or history upload."
                    )
                }
            }
        }
    }

    private var broadcastStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            SetupTitle(
                eyebrow: "WHOOP",
                title: "Turn on Heart Rate Broadcast",
                detail: "Pulse Notch can only see live heart rate while WHOOP is broadcasting it over Bluetooth."
            )

            FocusDotCard {
                VStack(alignment: .leading, spacing: 16) {
                    NumberedSetupRow(number: 1, text: "Open the WHOOP app on your phone.")
                    NumberedSetupRow(number: 2, text: "Tap the device indicator at the top right, then Device Settings.")
                    NumberedSetupRow(number: 3, text: "Under Status, turn on Heart Rate Broadcast.")
                }
            }

            SetupNote(
                icon: "bolt.horizontal.circle",
                text: "Keep WHOOP snug on your wrist and near this Mac. Broadcast can remain enabled while the WHOOP app continues syncing normally."
            )
        }
    }

    private var bluetoothStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            SetupTitle(
                eyebrow: "MAC PERMISSION",
                title: "Allow Bluetooth access",
                detail: "macOS may ask once. Pulse Notch uses Bluetooth only to find the monitor you select and receive live readings."
            )

            BluetoothPermissionCard(model: model)

            SetupNote(
                icon: "hand.raised.fill",
                text: "Pulse Notch cannot inspect other device data or your WHOOP account through this permission."
            )
        }
    }

    private var deviceStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            SetupTitle(
                eyebrow: "CONNECT",
                title: "Choose your WHOOP",
                detail: "Keep Heart Rate Broadcast on. Select your device explicitly if more than one monitor appears."
            )

            ConnectionResilienceCard(model: model, showsDeviceResults: true)
        }
    }

    private var thresholdStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            SetupTitle(
                eyebrow: "HEART RATE CUE",
                title: "Choose your heart rate threshold",
                detail: "This is the heart rate at which Pulse Notch starts a quiet timer. It only alerts if the reading stays elevated for your chosen duration."
            )

            FocusDotCard {
                VStack(alignment: .leading, spacing: 17) {
                    LabeledBPMControl(
                        title: "Heart Rate Threshold",
                        detail: "Adjust anytime after setup.",
                        value: heartRateThresholdBinding
                    )

                    Divider().overlay(FocusDotTheme.border)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sustained duration")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(FocusDotTheme.textPrimary)
                            Spacer()
                            Text("\(Int(model.settings.alerts.dwellSeconds)) sec")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(FocusDotTheme.liveHighlight)
                        }
                        Slider(value: dwellBinding, in: 15...120, step: 5)
                            .tint(FocusDotTheme.live)
                            .pointingHandCursor()
                        Text("A longer duration filters out brief heart-rate spikes.")
                            .font(.system(size: 11))
                            .foregroundStyle(FocusDotTheme.textTertiary)
                    }
                }
            }

            SetupNote(
                icon: "info.circle",
                text: "This cue does not identify stress, danger, or a health condition. Pause it whenever it is not useful."
            )
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            SetupTitle(
                eyebrow: "OPTIONAL",
                title: "Allow one calm reminder",
                detail: "A notification is sent only after your heart rate remains above the heart rate threshold for the sustained duration."
            )

            NotificationPermissionCard(
                model: model,
                permission: $notificationPermission,
                soundEnabled: $alertSoundEnabled
            )

            SetupNote(
                icon: "bell.slash",
                text: "You can continue without notifications. The live Focus Dot still works, and you can enable reminders later."
            )
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            FocusDotMark(size: 54)

            SetupTitle(
                eyebrow: "READY",
                title: "Your heart rate cue is set",
                detail: "Pulse Notch will stay compact until you click it. Your settings and live readings remain on this Mac."
            )

            FocusDotCard {
                VStack(alignment: .leading, spacing: 14) {
                    ReadyRow(
                        icon: model.connectionStatus.isLive ? "checkmark.circle.fill" : "clock.fill",
                        title: "WHOOP",
                        value: model.connectionStatus.isLive ? "Connected" : "Connect later"
                    )
                    ReadyRow(
                        icon: "gauge.with.dots.needle.50percent",
                        title: "Heart Rate Threshold",
                        value: "\(model.settings.alerts.bpmThreshold) BPM for \(Int(model.settings.alerts.dwellSeconds)) sec"
                    )
                    ReadyRow(
                        icon: remindersAreOn ? "bell.fill" : "bell.slash.fill",
                        title: "Reminders",
                        value: remindersAreOn ? "On" : "Off"
                    )
                }
            }
        }
    }

    private var remindersAreOn: Bool {
        notificationsEnabled && notificationPermission.allowsAlerts
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back", action: moveBack)
                    .buttonStyle(FocusDotActionButtonStyle(.secondary))
                    .frame(width: 96)
            }

            Spacer()

            if step == .device, !model.connectionStatus.isLive {
                Button("Connect later", action: moveForward)
                    .buttonStyle(FocusDotActionButtonStyle(.quiet))
                    .frame(width: 110)
            }

            Button(primaryButtonTitle, action: moveForward)
                .buttonStyle(FocusDotActionButtonStyle(.primary))
                .frame(width: step == .welcome ? 154 : 116)
                .disabled(!canMoveForward)
                .opacity(canMoveForward ? 1 : 0.45)
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
        .background(FocusDotTheme.notch.opacity(0.45))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FocusDotTheme.border)
                .frame(height: 1)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: "Set up WHOOP"
        case .device: "Continue"
        case .ready: "Finish"
        default: "Continue"
        }
    }

    private var canMoveForward: Bool {
        switch step {
        case .bluetooth:
            return model.connectionStatus.bluetoothIsAvailable
        case .device:
            return model.connectionStatus.isLive
                && model.approvedDeviceID == model.connectedDeviceID
        default:
            return true
        }
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

    private func moveBack() {
        guard let previous = SetupStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func moveForward() {
        if step == .ready {
            enableThresholdMonitoring()
            onComplete()
            return
        }
        guard let next = SetupStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func enableThresholdMonitoring() {
        var alerts = model.settings.alerts
        alerts.mode = .bpm
        alerts.isEnabled = true
        model.settings.alerts = alerts
    }
}

private enum SetupStep: Int, CaseIterable, Identifiable {
    case welcome
    case broadcast
    case bluetooth
    case device
    case threshold
    case notifications
    case ready

    var id: Int { rawValue }
}

struct FocusDotMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(FocusDotTheme.live.opacity(0.12))
                .frame(width: size, height: size)
            Circle()
                .stroke(FocusDotTheme.live.opacity(0.28), lineWidth: 1)
                .frame(width: size * 0.72, height: size * 0.72)
            Circle()
                .fill(FocusDotTheme.live)
                .frame(width: size * 0.22, height: size * 0.22)
                .shadow(color: FocusDotTheme.live.opacity(0.62), radius: 8)
        }
        .accessibilityHidden(true)
    }
}

struct SetupTitle: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(FocusDotTheme.liveHighlight)
            Text(title)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(FocusDotTheme.textPrimary)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(FocusDotTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }
}

struct FocusDotCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FocusDotTheme.raised)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FocusDotTheme.border, lineWidth: 1)
            }
    }
}

private struct SetupBenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FocusDotTheme.liveHighlight)
                .frame(width: 24, height: 24)
                .background(FocusDotTheme.live.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FocusDotTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(FocusDotTheme.textSecondary)
            }
        }
    }
}

private struct NumberedSetupRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(FocusDotTheme.live, in: Circle())
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FocusDotTheme.textPrimary)
                .padding(.top, 3)
        }
    }
}

struct SetupNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(FocusDotTheme.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(FocusDotTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BluetoothPermissionCard: View {
    @ObservedObject var model: HeartRateAppModel

    var body: some View {
        FocusDotCard {
            HStack(alignment: .top, spacing: 13) {
                StatusGlyph(icon: presentation.icon, tint: presentation.tint, showsProgress: presentation.showsProgress)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FocusDotTheme.textPrimary)
                    Text(presentation.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(FocusDotTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let action = presentation.action {
                    Button(action.title) { perform(action.kind) }
                        .buttonStyle(FocusDotActionButtonStyle(action.kind == .scan ? .primary : .secondary))
                        .frame(width: action.width)
                }
            }
        }
    }

    private var presentation: BluetoothPresentation {
        switch model.connectionStatus {
        case .waitingForBluetooth:
            return .init(
                icon: "wave.3.right",
                tint: FocusDotTheme.unavailable,
                title: "Checking Bluetooth",
                detail: "Waiting for macOS to report Bluetooth availability.",
                showsProgress: true,
                action: nil
            )
        case .bluetoothOff:
            return .init(
                icon: "wave.3.right.slash",
                tint: FocusDotTheme.elevated,
                title: "Bluetooth is off",
                detail: "Turn it on in System Settings, then return here.",
                showsProgress: false,
                action: .init(title: "Open Settings", width: 104, kind: .bluetoothSettings)
            )
        case .unauthorized:
            return .init(
                icon: "lock.fill",
                tint: FocusDotTheme.elevated,
                title: "Bluetooth access is blocked",
                detail: "Allow Pulse Notch under Privacy & Security → Bluetooth.",
                showsProgress: false,
                action: .init(title: "Open Privacy", width: 100, kind: .bluetoothPrivacy)
            )
        case let .failed(message):
            return .init(
                icon: "exclamationmark.triangle.fill",
                tint: FocusDotTheme.elevated,
                title: "Bluetooth is unavailable",
                detail: message,
                showsProgress: false,
                action: .init(title: "Try Again", width: 88, kind: .scan)
            )
        default:
            return .init(
                icon: "checkmark.circle.fill",
                tint: FocusDotTheme.live,
                title: "Bluetooth is ready",
                detail: "Pulse Notch can scan for nearby heart-rate broadcasts.",
                showsProgress: false,
                action: nil
            )
        }
    }

    private func perform(_ action: ResilienceAction.Kind) {
        switch action {
        case .scan:
            model.startScanning()
        case .disconnect:
            model.disconnect()
        case .reconnect:
            model.disconnect()
            model.startScanning()
        case .bluetoothSettings:
            PulseNotchSystemSettings.openBluetooth()
        case .bluetoothPrivacy:
            PulseNotchSystemSettings.openBluetoothPrivacy()
        }
    }
}

struct ConnectionResilienceCard: View {
    @ObservedObject var model: HeartRateAppModel
    let showsDeviceResults: Bool

    var body: some View {
        FocusDotCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    StatusGlyph(icon: presentation.icon, tint: presentation.tint, showsProgress: presentation.showsProgress)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FocusDotTheme.textPrimary)
                        Text(presentation.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(FocusDotTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    if let action = presentation.action {
                        Button(action.title) { perform(action.kind) }
                            .buttonStyle(FocusDotActionButtonStyle(action.kind == .scan ? .primary : .secondary))
                            .frame(width: action.width)
                    }
                }

                if showsDeviceResults, shouldShowDevices {
                    Divider().overlay(FocusDotTheme.border)
                    DeviceResultsList(model: model)
                }
            }
        }
    }

    private var shouldShowDevices: Bool {
        model.isScanningForDevices || !model.devices.isEmpty
    }

    private var presentation: ConnectionPresentation {
        if model.connectionStatus.isLive, model.sensorContactDetected == false {
            return .init(
                icon: "sensor.tag.radiowaves.forward.fill",
                tint: FocusDotTheme.elevated,
                title: "WHOOP contact lost",
                detail: "Adjust the band so the sensor sits snugly against your skin.",
                showsProgress: false,
                action: nil
            )
        }

        if model.connectionStatus.isLive, model.isStale {
            return .init(
                icon: "clock.badge.exclamationmark.fill",
                tint: FocusDotTheme.elevated,
                title: "Live signal is stale",
                detail: "No fresh reading has arrived. Pulse Notch will not treat the last BPM as live.",
                showsProgress: false,
                action: .init(title: "Reconnect", width: 92, kind: .reconnect)
            )
        }

        switch model.connectionStatus {
        case .waitingForBluetooth:
            return .init(
                icon: "wave.3.right",
                tint: FocusDotTheme.unavailable,
                title: "Checking Bluetooth",
                detail: "Waiting for macOS to report Bluetooth availability.",
                showsProgress: true,
                action: nil
            )
        case .bluetoothOff:
            return .init(
                icon: "wave.3.right.slash",
                tint: FocusDotTheme.elevated,
                title: "Bluetooth is off",
                detail: "Turn Bluetooth on, then return to scan for WHOOP.",
                showsProgress: false,
                action: .init(title: "Open Settings", width: 104, kind: .bluetoothSettings)
            )
        case .unauthorized:
            return .init(
                icon: "lock.fill",
                tint: FocusDotTheme.elevated,
                title: "Bluetooth permission denied",
                detail: "Allow Pulse Notch under Privacy & Security → Bluetooth.",
                showsProgress: false,
                action: .init(title: "Open Privacy", width: 100, kind: .bluetoothPrivacy)
            )
        case .idle:
            return .init(
                icon: "dot.radiowaves.left.and.right",
                tint: FocusDotTheme.unavailable,
                title: "No WHOOP connected",
                detail: "Turn on Heart Rate Broadcast, then scan nearby devices.",
                showsProgress: false,
                action: .init(title: "Scan", width: 76, kind: .scan)
            )
        case .scanning:
            return .init(
                icon: "dot.radiowaves.left.and.right",
                tint: FocusDotTheme.live,
                title: "Looking for WHOOP",
                detail: model.devices.isEmpty ? "Keep WHOOP nearby with Heart Rate Broadcast enabled." : "Select the device that belongs to you.",
                showsProgress: true,
                action: model.devices.isEmpty ? nil : .init(title: "Rescan", width: 82, kind: .scan)
            )
        case let .connecting(name), let .discovering(name), let .subscribing(name):
            return .init(
                icon: "link",
                tint: FocusDotTheme.live,
                title: "Connecting to \(name)",
                detail: model.connectionStatus.text,
                showsProgress: true,
                action: .init(title: "Cancel", width: 76, kind: .disconnect)
            )
        case let .live(name):
            return .init(
                icon: "checkmark.circle.fill",
                tint: FocusDotTheme.live,
                title: "Live from \(name)",
                detail: model.approvedDeviceID == model.connectedDeviceID
                    ? "Approved for automatic reconnect · \(model.lastReadingDescription)"
                    : "Waiting for the first live heart-rate reading before approval.",
                showsProgress: false,
                action: .init(title: "Disconnect", width: 94, kind: .disconnect)
            )
        case let .reconnecting(name, attempt):
            return .init(
                icon: "arrow.clockwise",
                tint: FocusDotTheme.live,
                title: "Reconnecting to \(name)",
                detail: "Automatic retry \(attempt). Keep WHOOP nearby and broadcasting.",
                showsProgress: true,
                action: .init(title: "Scan Again", width: 96, kind: .scan)
            )
        case let .incompatible(message):
            return .init(
                icon: "exclamationmark.triangle.fill",
                tint: FocusDotTheme.elevated,
                title: "No compatible live signal",
                detail: message,
                showsProgress: false,
                action: .init(title: "Rescan", width: 82, kind: .scan)
            )
        case let .failed(message):
            return .init(
                icon: "exclamationmark.triangle.fill",
                tint: FocusDotTheme.elevated,
                title: "Connection failed",
                detail: message,
                showsProgress: false,
                action: .init(title: "Rescan", width: 82, kind: .scan)
            )
        }
    }

    private func perform(_ action: ResilienceAction.Kind) {
        switch action {
        case .scan:
            model.startScanning()
        case .disconnect:
            model.disconnect()
        case .reconnect:
            model.disconnect()
            model.startScanning()
        case .bluetoothSettings:
            PulseNotchSystemSettings.openBluetooth()
        case .bluetoothPrivacy:
            PulseNotchSystemSettings.openBluetoothPrivacy()
        }
    }
}

private struct DeviceResultsList: View {
    @ObservedObject var model: HeartRateAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.devices.isEmpty {
                emptyState
            } else {
                HStack(spacing: 8) {
                    Text("HEART-RATE DEVICES")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(FocusDotTheme.textTertiary)

                    Spacer()

                    if model.isScanningForDevices {
                        ProgressView()
                            .controlSize(.mini)
                        Text("SCANNING")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(FocusDotTheme.textTertiary)
                    }
                }

                ForEach(model.devices) { device in
                    deviceRow(device)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            if model.isScanningForDevices {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .foregroundStyle(FocusDotTheme.textTertiary)
            }

            Text(
                model.isScanningForDevices
                    ? "Scanning nearby heart-rate broadcasts…"
                    : "No heart-rate devices found. Rescan when WHOOP Broadcast is on."
            )
            .font(.system(size: 11))
            .foregroundStyle(FocusDotTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deviceRow(_ device: DiscoveredHeartRateDevice) -> some View {
        let isConnected = model.connectedDeviceID == device.id
        let isApproved = model.approvedDeviceID == device.id
        let isConnecting = model.connectingDeviceID == device.id

        return HStack(spacing: 11) {
            Image(
                systemName: isConnected
                    ? "sensor.tag.radiowaves.forward.fill"
                    : "sensor.tag.radiowaves.forward"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isConnected ? FocusDotTheme.live : FocusDotTheme.liveHighlight)
            .frame(width: 26, height: 26)
            .background(
                FocusDotTheme.live.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 8)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FocusDotTheme.textPrimary)

                HStack(spacing: 7) {
                    DeviceStateLabel(
                        title: signalLabel(device.rssi),
                        icon: "cellularbars",
                        tint: FocusDotTheme.textTertiary
                    )

                    if isConnected {
                        DeviceStateLabel(
                            title: "Connected",
                            icon: "link",
                            tint: FocusDotTheme.live
                        )
                    }

                    if isApproved {
                        DeviceStateLabel(
                            title: "Approved",
                            icon: "checkmark.seal.fill",
                            tint: FocusDotTheme.live
                        )
                    }
                }
            }

            Spacer(minLength: 8)

            deviceAction(
                for: device,
                isConnected: isConnected,
                isApproved: isApproved,
                isConnecting: isConnecting
            )
        }
        .padding(10)
        .background(
            FocusDotTheme.notch.opacity(0.32),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    @ViewBuilder
    private func deviceAction(
        for device: DiscoveredHeartRateDevice,
        isConnected: Bool,
        isApproved: Bool,
        isConnecting: Bool
    ) -> some View {
        if isConnecting {
            Button("Connecting…") {}
                .buttonStyle(FocusDotActionButtonStyle(.secondary))
                .frame(width: 104)
                .disabled(true)
                .accessibilityLabel("Connecting to \(device.name)")
        } else if isConnected {
            Button("In Use") {}
                .buttonStyle(FocusDotActionButtonStyle(.secondary))
                .frame(width: 88)
                .disabled(true)
                .accessibilityLabel("\(device.name) is in use")
        } else if isApproved {
            Button("Connect") {
                model.connect(to: device.id)
            }
            .buttonStyle(FocusDotActionButtonStyle(.secondary))
            .frame(width: 82)
            .accessibilityLabel("Connect to approved device \(device.name)")
            .accessibilityHint("Reconnects only to this approved heart-rate device.")
        } else {
            Button("Use This Device") {
                model.connect(to: device.id)
            }
            .buttonStyle(FocusDotActionButtonStyle(.primary))
            .frame(width: 126)
            .accessibilityLabel("Use \(device.name)")
            .accessibilityHint("Connects to this device and approves it after the first live heart-rate reading.")
        }
    }

    private func signalLabel(_ rssi: Int) -> String {
        if rssi == 127 { return "Signal unavailable" }
        if rssi >= -60 { return "Strong signal" }
        if rssi >= -75 { return "Good signal" }
        return "Weak signal"
    }
}

private struct DeviceStateLabel: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

private struct StatusGlyph: View {
    let icon: String
    let tint: Color
    let showsProgress: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct ConnectionPresentation {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let showsProgress: Bool
    let action: ResilienceAction?
}

private struct BluetoothPresentation {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let showsProgress: Bool
    let action: ResilienceAction?
}

private struct ResilienceAction {
    enum Kind: Equatable {
        case scan
        case disconnect
        case reconnect
        case bluetoothSettings
        case bluetoothPrivacy
    }

    let title: String
    let width: CGFloat
    let kind: Kind
}

struct LabeledBPMControl: View {
    let title: String
    let detail: String
    @Binding var value: Int

    @State private var draftValue: String
    @FocusState private var isEditingValue: Bool

    init(title: String, detail: String, value: Binding<Int>) {
        self.title = title
        self.detail = detail
        _value = value
        _draftValue = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FocusDotTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(FocusDotTheme.textTertiary)
            }

            Spacer()

            TextField("BPM", text: $draftValue)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(FocusDotTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .focused($isEditingValue)
                .frame(width: 50)
                .frame(height: 30)
                .padding(.horizontal, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isEditingValue ? FocusDotTheme.hover : FocusDotTheme.raised)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isEditingValue ? FocusDotTheme.live.opacity(0.8) : FocusDotTheme.border,
                            lineWidth: 1
                        )
                }
                .onSubmit(commitDraftValue)
                .onChange(of: isEditingValue) { isEditing in
                    if !isEditing {
                        commitDraftValue()
                    }
                }
                .onChange(of: draftValue) { newValue in
                    let numericValue = BPMThresholdInput.sanitizeDraft(newValue)
                    if numericValue != newValue {
                        draftValue = numericValue
                    }
                }
                .onChange(of: value) { newValue in
                    if !isEditingValue {
                        draftValue = String(newValue)
                    }
                }
                .onDisappear(perform: commitDraftValue)
                .accessibilityLabel("\(title) in beats per minute")
            Text("BPM")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(FocusDotTheme.textTertiary)

            Stepper("", value: stepperValue, in: BPMThresholdInput.allowedRange)
                .labelsHidden()
                .accessibilityLabel("Adjust \(title.lowercased())")
                .pointingHandCursor()
        }
    }

    private var stepperValue: Binding<Int> {
        Binding(
            get: {
                BPMThresholdInput.committedValue(from: draftValue, currentValue: value)
            },
            set: { newValue in
                value = newValue
                draftValue = String(newValue)
            }
        )
    }

    private func commitDraftValue() {
        let committedValue = BPMThresholdInput.committedValue(from: draftValue, currentValue: value)
        value = committedValue
        draftValue = String(committedValue)
    }
}

struct NotificationPermissionCard: View {
    @ObservedObject var model: HeartRateAppModel
    @Binding var permission: PulseNotificationPermission
    @Binding var soundEnabled: Bool
    @AppStorage("pulseNotch.notificationsEnabled.v1") private var notificationsEnabled = false

    var body: some View {
        FocusDotCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    StatusGlyph(
                        icon: permission.icon,
                        tint: permission.tint,
                        showsProgress: permission == .checking
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(permission.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FocusDotTheme.textPrimary)
                        Text(permission.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(FocusDotTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    permissionAction
                }

                if permission.allowsAlerts {
                    Divider().overlay(FocusDotTheme.border)
                    Toggle("Play a soft notification sound", isOn: $soundEnabled)
                        .toggleStyle(.switch)
                        .tint(FocusDotTheme.live)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FocusDotTheme.textPrimary)
                        .pointingHandCursor()
                }
            }
        }
    }

    @ViewBuilder
    private var permissionAction: some View {
        switch permission {
        case .notDetermined:
            Button("Allow", action: requestPermission)
                .buttonStyle(FocusDotActionButtonStyle(.primary))
                .frame(width: 78)
        case .denied:
            Button("Open Settings", action: PulseNotchSystemSettings.openNotifications)
                .buttonStyle(FocusDotActionButtonStyle(.secondary))
                .frame(width: 104)
        case .authorized:
            Toggle("", isOn: reminderEnabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(FocusDotTheme.live)
                .pointingHandCursor()
        case .checking:
            EmptyView()
        }
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { notificationsEnabled = $0 }
        )
    }

    private func requestPermission() {
        permission = .checking
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationsEnabled = granted
                PulseNotificationPermission.read { permission = $0 }
            }
        }
    }
}

private struct ReadyRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FocusDotTheme.liveHighlight)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FocusDotTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(FocusDotTheme.textSecondary)
        }
    }
}

enum PulseNotificationPermission: Equatable {
    case checking
    case notDetermined
    case authorized
    case denied

    static func read(completion: @escaping (PulseNotificationPermission) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let value: PulseNotificationPermission
            switch settings.authorizationStatus {
            case .notDetermined:
                value = .notDetermined
            case .denied:
                value = .denied
            case .authorized, .provisional, .ephemeral:
                value = .authorized
            @unknown default:
                value = .denied
            }
            DispatchQueue.main.async { completion(value) }
        }
    }

    var allowsAlerts: Bool { self == .authorized }

    fileprivate var icon: String {
        switch self {
        case .checking: "bell"
        case .notDetermined: "bell.badge"
        case .authorized: "checkmark.circle.fill"
        case .denied: "bell.slash.fill"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .authorized: FocusDotTheme.live
        case .denied: FocusDotTheme.elevated
        case .checking, .notDetermined: FocusDotTheme.unavailable
        }
    }

    fileprivate var title: String {
        switch self {
        case .checking: "Checking notification access"
        case .notDetermined: "Notifications are optional"
        case .authorized: "Notifications are allowed"
        case .denied: "Notifications are blocked"
        }
    }

    fileprivate var detail: String {
        switch self {
        case .checking: "Waiting for macOS notification settings."
        case .notDetermined: "Allow a factual reminder after a sustained threshold crossing."
        case .authorized: "Use the switch to pause or resume sustained reminders."
        case .denied: "Allow Pulse Notch in System Settings → Notifications."
        }
    }
}

enum PulseNotchSystemSettings {
    static func openBluetooth() {
        open(
            urls: ["x-apple.systempreferences:com.apple.Bluetooth-Settings.extension"],
            fallbackPath: "/System/Applications/System Settings.app"
        )
    }

    static func openBluetoothPrivacy() {
        open(
            urls: ["x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"],
            fallbackPath: "/System/Applications/System Settings.app"
        )
    }

    static func openNotifications() {
        open(
            urls: [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications"
            ],
            fallbackPath: "/System/Applications/System Settings.app"
        )
    }

    private static func open(urls: [String], fallbackPath: String) {
        for rawURL in urls {
            if let url = URL(string: rawURL), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: fallbackPath))
    }
}

extension BLEConnectionStatus {
    var bluetoothIsAvailable: Bool {
        switch self {
        case .waitingForBluetooth, .bluetoothOff, .unauthorized, .failed:
            return false
        default:
            return true
        }
    }
}
