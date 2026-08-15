import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HeartRateAppModel()
    private var overlayController: OverlayPanelController!
    private var settingsController: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsController = SettingsWindowController(model: model)
        overlayController = OverlayPanelController(model: model) { [weak self] in
            self?.openSettings()
        }
        configureStatusItem()
        overlayController.show()

        if let qaState = ProcessInfo.processInfo.environment["PULSE_NOTCH_QA_STATE"] {
            configureQAPreview(state: qaState)
        } else if let capturePath = ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_PATH"] {
            runPreviewCapture(path: capturePath)
        } else if !UserDefaults.standard.bool(forKey: "pulseNotch.onboardingComplete.v1") {
            settingsController.show()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.model.handleWake()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        model.shutdown()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "heart.fill",
                accessibilityDescription: "Pulse Notch"
            )
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show or Hide Pulse", action: #selector(toggleOverlay), keyEquivalent: "p")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Scan for Monitor", action: #selector(startScanning), keyEquivalent: "s")
        menu.addItem(withTitle: "Toggle Demo Signal", action: #selector(toggleSimulation), keyEquivalent: "d")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pulse Notch", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleOverlay() {
        overlayController.toggle()
    }

    @objc private func openSettings() {
        // Start collapsing the detail panel before activating another window.
        // The notch view observes this model change and routes it through the
        // same generation-guarded close sequence used by a direct notch click.
        if model.isExpanded {
            model.isExpanded = false
        }

        DispatchQueue.main.async { [weak self] in
            self?.settingsController.show()
        }
    }

    @objc private func startScanning() {
        model.startScanning()
        overlayController.show()
    }

    @objc private func toggleSimulation() {
        model.toggleSimulation()
        overlayController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func runPreviewCapture(path: String) {
        let state = ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_STATE"] ?? "expanded"
        let target = ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_TARGET"] ?? "overlay"
        let requestedName = URL(fileURLWithPath: path).lastPathComponent
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent(requestedName)
        let isThresholdOnboardingCapture = ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_ONBOARDING_STEP"] == "threshold"
        let isOpeningCapture = state == "opening"
        let isElevatedCapture = state == "elevated" || state == "elevated-collapsed" || isOpeningCapture
        let originalAlerts = model.settings.alerts
        var captureAlerts = originalAlerts
        captureAlerts.isEnabled = true
        captureAlerts.mode = .bpm
        captureAlerts.bpmThreshold = isThresholdOnboardingCapture ? 62 : (isElevatedCapture ? 100 : 210)
        captureAlerts.dwellSeconds = isThresholdOnboardingCapture ? 15 : (isElevatedCapture ? 5 : 20)
        model.settings.alerts = captureAlerts
        model.startSimulation(prefilling: 180)
        model.isExpanded = ["expanded", "elevated", "reset", "complete"].contains(state)
        if target == "settings" {
            settingsController.show()
        }

        if isOpeningCapture {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.model.isExpanded = true
            }
        }

        let captureDelay = isOpeningCapture ? 1.22 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [weak self] in
            guard let self else { return }
            do {
                if target == "settings" {
                    try self.settingsController.capturePreview(to: captureURL)
                } else {
                    try self.overlayController.capturePreview(to: captureURL)
                }
                fputs("Pulse Notch preview saved: \(captureURL.path)\n", stderr)
            } catch {
                fputs("Pulse Notch preview capture failed: \(error)\n", stderr)
            }
            self.model.settings.alerts = originalAlerts
            NSApp.terminate(nil)
        }
    }

    /// Keeps a deterministic simulated state onscreen for real desktop captures.
    /// Unlike the bitmap capture path, this preserves backdrop sampling for
    /// native Liquid Glass and never changes the user's alert configuration.
    private func configureQAPreview(state: String) {
        model.startSimulation(prefilling: 180)
        model.isExpanded = ["expanded", "elevated"].contains(state)

        if state == "opening" {
            model.isExpanded = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.model.isExpanded = true
            }
        }
    }
}
