import Foundation
import SwiftUI

enum FocusDotTheme {
    static let notch = Color.black
    static let panel = Color(red: 0.031, green: 0.039, blue: 0.051)
    static let glassPanelTint = Color(red: 0.025, green: 0.034, blue: 0.050).opacity(0.76)
    static let glassWingTint = Color(red: 0.030, green: 0.041, blue: 0.061).opacity(0.72)
    static let glassEdge = Color.white.opacity(0.18)
    static let glassInnerEdge = Color.white.opacity(0.055)
    static let glassHighlight = Color.white.opacity(0.13)
    static let raised = Color.white.opacity(0.06)
    static let hover = Color.white.opacity(0.10)
    static let pressed = Color.white.opacity(0.14)
    static let border = Color.white.opacity(0.08)

    static let textPrimary = Color(red: 0.961, green: 0.969, blue: 0.980)
    static let textSecondary = Color(red: 0.655, green: 0.678, blue: 0.718)
    static let textTertiary = Color(red: 0.439, green: 0.467, blue: 0.510)

    static let live = Color(red: 0.039, green: 0.518, blue: 1.000)
    static let liveHighlight = Color(red: 0.392, green: 0.824, blue: 1.000)
    static let elevated = Color(red: 1.000, green: 0.624, blue: 0.039)
    static let elevatedHighlight = Color(red: 1.000, green: 0.824, blue: 0.478)
    static let unavailable = Color(red: 0.431, green: 0.455, blue: 0.490)
}

extension Animation {
    static let focusDotContentOpen = focusDotSmooth(duration: 0.14)
    static let focusDotActionsOpen = focusDotSmooth(duration: 0.16)
    static let focusDotContentClose = focusDotSmooth(duration: 0.11)
    static let focusDotActionsClose = focusDotSmooth(duration: 0.09)
    static let focusDotPress = focusDotSmooth(duration: 0.12)

    private static func focusDotSmooth(duration: TimeInterval) -> Animation {
        if #available(macOS 14.0, *) {
            return .smooth(duration: duration, extraBounce: 0)
        }
        return .spring(response: duration, dampingFraction: 1, blendDuration: 0.03)
    }
}

struct FocusDotIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FocusDotTheme.textPrimary)
            .frame(width: 34, height: 34)
            .background {
                AdaptiveGlassSurface(
                    cornerRadius: 10,
                    tint: .white,
                    tintOpacity: configuration.isPressed ? 0.07 : 0.025,
                    isInteractive: true,
                    reflectionIntensity: 0.65
                )
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .focusDotPress, value: configuration.isPressed)
            .pointingHandCursor()
    }
}

struct FocusDotActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case quiet
    }

    let kind: Kind
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ kind: Kind, tint: Color = FocusDotTheme.live) {
        self.kind = kind
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(kind == .primary ? Color.white : FocusDotTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: kind == .quiet ? 26 : 36)
            .background(background(isPressed: configuration.isPressed))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(configuration.isPressed ? 0.18 : 0.12), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .animation(reduceMotion ? nil : .focusDotPress, value: configuration.isPressed)
            .pointingHandCursor()
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch kind {
        case .primary:
            AdaptiveGlassSurface(
                cornerRadius: 10,
                tint: tint,
                tintOpacity: isPressed ? 0.20 : 0.28,
                isInteractive: true,
                highlighted: !isPressed,
                reflectionIntensity: 0.65
            )
        case .secondary:
            AdaptiveGlassSurface(
                cornerRadius: 10,
                tint: .white,
                tintOpacity: isPressed ? 0.07 : 0.02,
                isInteractive: true,
                reflectionIntensity: 0.65
            )
        case .quiet:
            Color.clear
        }
    }
}
