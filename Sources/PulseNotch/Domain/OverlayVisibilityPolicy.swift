import Foundation

enum DisplayPreferenceKeys {
    static let compactInFullscreen = "pulseNotch.fullscreenCompactOnly.v1"
    static let hideInFullscreen = "pulseNotch.hideInFullscreen.v1"
    static let presentationPrivacy = "pulseNotch.presentationPrivacy.v1"
}

struct OverlayVisibilityDecision: Equatable {
    let shouldShow: Bool
    let shouldCollapse: Bool
}

struct FullscreenRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

enum FullscreenCoordinateSpace {
    static func quartzVisibleFrame(
        appKitScreenFrame: FullscreenRect,
        appKitVisibleFrame: FullscreenRect,
        quartzDisplayBounds: FullscreenRect
    ) -> FullscreenRect? {
        guard appKitScreenFrame.width > 0,
              appKitScreenFrame.height > 0,
              appKitVisibleFrame.width > 0,
              appKitVisibleFrame.height > 0,
              quartzDisplayBounds.width > 0,
              quartzDisplayBounds.height > 0 else {
            return nil
        }

        let scaleX = quartzDisplayBounds.width / appKitScreenFrame.width
        let scaleY = quartzDisplayBounds.height / appKitScreenFrame.height
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else {
            return nil
        }

        // AppKit's screen space grows upward; Quartz's display/window space grows
        // downward. Insets relative to this screen avoid assumptions about which
        // display is primary or where another display sits globally.
        let leftInset = max(0, appKitVisibleFrame.minX - appKitScreenFrame.minX)
        let topInset = max(0, appKitScreenFrame.maxY - appKitVisibleFrame.maxY)
        return FullscreenRect(
            x: quartzDisplayBounds.minX + leftInset * scaleX,
            y: quartzDisplayBounds.minY + topInset * scaleY,
            width: appKitVisibleFrame.width * scaleX,
            height: appKitVisibleFrame.height * scaleY
        )
    }
}

struct FullscreenWindowGeometry: Equatable, Sendable {
    let bounds: FullscreenRect
    let layer: Int
    let alpha: Double
}

enum ActiveAppFullscreenPolicy {
    /// Combines AppKit's authoritative signal for native full screen with a
    /// geometry fallback for apps that implement a screen-covering window
    /// without setting `NSApplicationPresentationFullScreen`.
    static func isFullscreen(
        frontmostAppIsOwnApp: Bool,
        presentationReportsFullscreen: Bool,
        targetDisplayBounds: FullscreenRect?,
        targetVisibleFrameBounds: FullscreenRect?,
        frontmostWindows: [FullscreenWindowGeometry]
    ) -> Bool {
        guard !frontmostAppIsOwnApp else { return false }
        if presentationReportsFullscreen { return true }

        let targetFrames = [targetDisplayBounds, targetVisibleFrameBounds]
            .compactMap { $0 }
            .filter(isUsable)
        guard !targetFrames.isEmpty else { return false }

        return frontmostWindows.contains { window in
            window.layer == 0
                && window.alpha > 0.01
                && targetFrames.contains { targetFrame in
                    coversFrame(window.bounds, targetFrame: targetFrame)
                }
        }
    }

    static func coversFrame(
        _ windowBounds: FullscreenRect,
        targetFrame: FullscreenRect
    ) -> Bool {
        guard isUsable(windowBounds), isUsable(targetFrame) else { return false }

        // Quartz window/display bounds are in the same global coordinate space.
        // Allow a few points for rounding and borderless-window bookkeeping, but
        // keep the tolerance well below ordinary window chrome or insets within
        // either accepted target frame.
        let tolerance = max(3, min(targetFrame.width, targetFrame.height) * 0.002)
        return windowBounds.minX <= targetFrame.minX + tolerance
            && windowBounds.minY <= targetFrame.minY + tolerance
            && windowBounds.maxX >= targetFrame.maxX - tolerance
            && windowBounds.maxY >= targetFrame.maxY - tolerance
    }

    private static func isUsable(_ rect: FullscreenRect) -> Bool {
        rect.width > 0
            && rect.height > 0
            && rect.minX.isFinite
            && rect.minY.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
    }
}

enum OverlayVisibilityPolicy {
    static func decision(
        userWantsVisible: Bool,
        presentationPrivacyEnabled: Bool,
        hideInFullscreenEnabled: Bool,
        compactInFullscreenEnabled: Bool,
        isActiveAppFullscreen: Bool
    ) -> OverlayVisibilityDecision {
        let hidesForFullscreen = hideInFullscreenEnabled && isActiveAppFullscreen
        return OverlayVisibilityDecision(
            shouldShow: userWantsVisible && !presentationPrivacyEnabled && !hidesForFullscreen,
            shouldCollapse: isActiveAppFullscreen
                && (hideInFullscreenEnabled || compactInFullscreenEnabled)
        )
    }
}
