import AppKit
import SwiftUI

/// Gives native macOS controls a clear clickable affordance without changing
/// the cursor used by editable text fields.
private struct PointingHandCursorModifier: ViewModifier {
    let enabled: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var hasPushedCursor = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .pointerStyle(cursorIsEnabled ? .link : nil)
        } else {
            content
                .onHover { hovering in
                    isHovering = hovering
                    setCursorActive(hovering && cursorIsEnabled)
                }
                .onChange(of: cursorIsEnabled) { active in
                    setCursorActive(active && isHovering)
                }
                .onDisappear {
                    setCursorActive(false)
                }
        }
    }

    private var cursorIsEnabled: Bool {
        enabled && isEnabled
    }

    private func setCursorActive(_ active: Bool) {
        guard active != hasPushedCursor else { return }

        if active {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
        hasPushedCursor = active
    }
}

extension View {
    func pointingHandCursor(_ enabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(enabled: enabled))
    }
}
