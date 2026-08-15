import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(model: HeartRateAppModel) {
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pulse Notch Settings"
        window.contentView = hostingView
        window.minSize = NSSize(width: 600, height: 660)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func capturePreview(to url: URL) throws {
        guard let window,
              let view = window.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw SettingsPreviewCaptureError.couldNotCreateBitmap
        }
        window.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SettingsPreviewCaptureError.couldNotEncodePNG
        }
        try data.write(to: url, options: .atomic)
    }
}

private enum SettingsPreviewCaptureError: Error {
    case couldNotCreateBitmap
    case couldNotEncodePNG
}
