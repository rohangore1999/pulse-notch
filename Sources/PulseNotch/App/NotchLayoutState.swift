import Combine
import CoreGraphics

final class NotchLayoutState: ObservableObject {
    @Published private(set) var hasPhysicalNotch = false
    @Published private(set) var notchWidth: CGFloat = 0
    @Published private(set) var notchHeight: CGFloat = 0

    /// Drawable width on each side of the physical camera housing.
    let compactWingWidth: CGFloat = 134
    let attachmentOverlap: CGFloat = 8
    let fallbackWidth: CGFloat = 360
    let fallbackHeight: CGFloat = 42
    let expandedBodyWidth: CGFloat = 488
    let expandedHeight: CGFloat = 306

    /// Compatibility helpers for views that express the compact geometry as an
    /// extension around the camera housing. The extension is horizontal only:
    /// compact content shares the camera cutout's vertical strip.
    var compactExtraWidth: CGFloat { compactWingWidth * 2 }
    var compactExtensionHeight: CGFloat {
        hasPhysicalNotch ? notchHeight : fallbackHeight
    }

    var collapsedWidth: CGFloat {
        hasPhysicalNotch ? notchWidth + compactWingWidth * 2 : fallbackWidth
    }

    var collapsedHeight: CGFloat {
        hasPhysicalNotch ? notchHeight : fallbackHeight
    }

    func update(hasPhysicalNotch: Bool, notchWidth: CGFloat, notchHeight: CGFloat) {
        self.hasPhysicalNotch = hasPhysicalNotch
        self.notchWidth = hasPhysicalNotch ? max(0, notchWidth) : 0
        self.notchHeight = hasPhysicalNotch ? max(0, notchHeight) : 0
    }

    func panelSize(expanded: Bool) -> CGSize {
        if expanded {
            return CGSize(width: max(collapsedWidth, expandedBodyWidth), height: expandedHeight)
        }
        return CGSize(width: collapsedWidth, height: collapsedHeight)
    }
}
