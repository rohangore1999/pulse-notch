enum OutsideClickDismissalPolicy {
    static func shouldCollapse(
        isExpanded: Bool,
        overlayIsVisible: Bool,
        userWantsOverlayVisible: Bool,
        clickIsInsideOverlay: Bool
    ) -> Bool {
        isExpanded
            && overlayIsVisible
            && userWantsOverlayVisible
            && !clickIsInsideOverlay
    }
}
