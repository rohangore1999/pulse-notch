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

        if !UserDefaults.standard.bool(forKey: "pulseNotch.onboardingComplete.v1") {
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
