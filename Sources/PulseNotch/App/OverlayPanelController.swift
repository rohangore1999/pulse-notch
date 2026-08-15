import AppKit
import Combine
import QuartzCore
import SwiftUI

final class FloatingNotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class OverlayPanelController {
    private let model: HeartRateAppModel
    private let layout = NotchLayoutState()
    private let panel: FloatingNotchPanel
    private var cancellables: Set<AnyCancellable> = []
    private var presentationPrivacyEnabled: Bool
    private var hideInFullscreenEnabled: Bool
    private var compactInFullscreenEnabled: Bool
    private var isActiveAppFullscreen = false
    private var userWantsOverlayVisible = false
    private var fullscreenRefreshWorkItems: [DispatchWorkItem] = []
    private var frameAnimationGeneration: UInt = 0
    private var requestedPanelFrame: NSRect?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private static let outsideClickEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    private static let openTiming = CAMediaTimingFunction(
        controlPoints: 0.22,
        1.0,
        0.36,
        1.0
    )
    private static let closeTiming = CAMediaTimingFunction(
        controlPoints: 0.20,
        0.75,
        0.30,
        1.0
    )
    private static let fullscreenRefreshRetryDelay: TimeInterval = 0.55

    init(model: HeartRateAppModel, openSettings: @escaping () -> Void) {
        self.model = model
        presentationPrivacyEnabled = Self.boolPreference(
            DisplayPreferenceKeys.presentationPrivacy,
            defaultValue: false
        )
        hideInFullscreenEnabled = Self.boolPreference(
            DisplayPreferenceKeys.hideInFullscreen,
            defaultValue: false
        )
        compactInFullscreenEnabled = Self.boolPreference(
            DisplayPreferenceKeys.compactInFullscreen,
            defaultValue: true
        )
        panel = FloatingNotchPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 42)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let rootView = NotchPillView(model: model, layout: layout, openSettings: openSettings)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Status-bar level lets the compact wings occupy the drawable menu-bar
        // strip on either side of the physical camera housing.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        // Window-level appearance animation is handled explicitly below. Using
        // utilityWindow here adds a second, unrelated animation when the panel
        // is ordered in or out and makes the notch transition feel disconnected.
        panel.animationBehavior = .none

        model.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.updateOutsideClickMonitoring(expanded: expanded)
                self?.resize(expanded: expanded, animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.positionPanel(animated: false)
                self?.scheduleFullscreenRefresh(after: 0.2)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.scheduleFullscreenRefresh(after: 0.35)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.scheduleFullscreenRefresh(after: 0.12) }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.scheduleFullscreenRefresh(after: 0.4) }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )
        .sink { [weak self] _ in self?.handleAccessibilityDisplayOptionsChange() }
        .store(in: &cancellables)

        NSApp.publisher(for: \.currentSystemPresentationOptions, options: [.initial, .new])
            .sink { [weak self] _ in self?.scheduleFullscreenRefresh(after: 0.05) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.applyDisplayPreferences() }
            .store(in: &cancellables)

        positionPanel(animated: false)
    }

    deinit {
        removeOutsideClickMonitoring()
        fullscreenRefreshWorkItems.forEach { $0.cancel() }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        userWantsOverlayVisible = true
        refreshFullscreenState()
    }

    func hide() {
        userWantsOverlayVisible = false
        reconcileVisibility()
    }

    func toggle() {
        userWantsOverlayVisible.toggle()
        refreshFullscreenState()
    }

    private func resize(expanded: Bool, animated: Bool) {
        positionPanel(expanded: expanded, animated: animated)
    }

    private func positionPanel(animated: Bool) {
        positionPanel(expanded: model.isExpanded, animated: animated)
    }

    private func positionPanel(expanded: Bool, animated: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.positionPanel(expanded: expanded, animated: animated)
            }
            return
        }
        guard let screen = targetScreen else { return }
        updateLayout(for: screen)
        let resolvedSize = layout.panelSize(expanded: expanded)
        let centerX = physicalNotchRect(on: screen)?.midX ?? screen.frame.midX
        let frame = pixelSnappedFrame(
            centeredAt: centerX,
            top: screen.frame.maxY,
            size: resolvedSize,
            scale: screen.backingScaleFactor
        )
        setPanelFrame(frame, expanded: expanded, animated: animated)
    }

    private func setPanelFrame(_ frame: NSRect, expanded: Bool, animated: Bool) {
        let targetMatchesRequest = requestedPanelFrame.map {
            framesMatch($0, frame)
        } ?? false
        if NotchFrameAnimationPolicy.preservesMatchingRequest(
            panelIsVisible: panel.isVisible,
            targetMatchesRequest: targetMatchesRequest,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) {
            return
        }

        frameAnimationGeneration &+= 1
        let generation = frameAnimationGeneration
        requestedPanelFrame = frame

        let shouldAnimate = animated
            && panel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !framesMatch(panel.frame, frame)

        guard shouldAnimate else {
            panel.setFrame(frame, display: true)
            requestedPanelFrame = nil
            return
        }

        let duration = expanded
            ? NotchMotionMetrics.panelOpenDuration
            : NotchMotionMetrics.panelCloseDuration
        let displaysDuringAnimation = NotchMotionMetrics.displaysDuringFrameAnimation(
            expanded: expanded
        )
        let completion: () -> Void = { [weak self] in
            guard let self,
                  self.frameAnimationGeneration == generation else { return }

            // Finish on an exact backing-pixel boundary. The generation guard
            // prevents an older completion from winning after a rapid reversal.
            self.panel.setFrame(frame, display: true)
            self.requestedPanelFrame = nil
        }

        if #available(macOS 15.0, *) {
            NSAnimationContext.animate(
                .smooth(duration: duration, extraBounce: 0),
                changes: { [panel = panel] in
                    panel.animator().setFrame(
                        frame,
                        display: displaysDuringAnimation
                    )
                },
                completion: completion
            )
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = expanded ? Self.openTiming : Self.closeTiming
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(
                    frame,
                    display: displaysDuringAnimation
                )
            } completionHandler: {
                completion()
            }
        }
    }

    private func handleAccessibilityDisplayOptionsChange() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleAccessibilityDisplayOptionsChange()
            }
            return
        }

        guard NotchFrameAnimationPolicy.finishesImmediatelyForReducedMotion(
            reduceMotionEnabled: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            hasInFlightFrame: requestedPanelFrame != nil
        ), let requestedPanelFrame else { return }

        frameAnimationGeneration &+= 1
        self.requestedPanelFrame = nil
        panel.setFrame(requestedPanelFrame, display: true)
    }

    private func pixelSnappedFrame(
        centeredAt centerX: CGFloat,
        top: CGFloat,
        size: CGSize,
        scale: CGFloat
    ) -> NSRect {
        let resolvedScale = max(1, scale)
        let snappedWidth = pixelSnap(size.width, scale: resolvedScale)
        let snappedHeight = pixelSnap(size.height, scale: resolvedScale)
        let snappedCenterX = pixelSnap(centerX, scale: resolvedScale)
        let snappedTop = pixelSnap(top, scale: resolvedScale)

        return NSRect(
            x: pixelSnap(snappedCenterX - snappedWidth / 2, scale: resolvedScale),
            y: pixelSnap(snappedTop - snappedHeight, scale: resolvedScale),
            width: snappedWidth,
            height: snappedHeight
        )
    }

    private func pixelSnap(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.01
            && abs(lhs.minY - rhs.minY) < 0.01
            && abs(lhs.width - rhs.width) < 0.01
            && abs(lhs.height - rhs.height) < 0.01
    }

    private func updateOutsideClickMonitoring(expanded: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateOutsideClickMonitoring(expanded: expanded)
            }
            return
        }

        let shouldMonitor = expanded
            && panel.isVisible
            && userWantsOverlayVisible

        if shouldMonitor {
            installOutsideClickMonitoringIfNeeded()
        } else {
            removeOutsideClickMonitoring()
        }
    }

    private func installOutsideClickMonitoringIfNeeded() {
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: Self.outsideClickEventMask
            ) { [weak self] event in
                guard let self else { return event }
                let clickIsInsideOverlay = event.window === self.panel
                    || event.windowNumber == self.panel.windowNumber
                self.handleMouseDown(clickIsInsideOverlay: clickIsInsideOverlay)
                return event
            }
        }

        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: Self.outsideClickEventMask
            ) { [weak self] _ in
                self?.handleMouseDown(clickIsInsideOverlay: false)
            }
        }
    }

    private func removeOutsideClickMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handleMouseDown(clickIsInsideOverlay: Bool) {
        guard !clickIsInsideOverlay else { return }

        // Keep the originating click untouched. Re-evaluating on the next main
        // loop also prevents a queued dismissal from affecting an overlay that
        // was hidden or collapsed by that click's own action.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  OutsideClickDismissalPolicy.shouldCollapse(
                      isExpanded: self.model.isExpanded,
                      overlayIsVisible: self.panel.isVisible,
                      userWantsOverlayVisible: self.userWantsOverlayVisible,
                      clickIsInsideOverlay: clickIsInsideOverlay
                  ) else { return }

            self.model.isExpanded = false
        }
    }

    private func applyDisplayPreferences() {
        let nextPrivacy = Self.boolPreference(
            DisplayPreferenceKeys.presentationPrivacy,
            defaultValue: false
        )
        let nextHideInFullscreen = Self.boolPreference(
            DisplayPreferenceKeys.hideInFullscreen,
            defaultValue: false
        )
        let nextCompactInFullscreen = Self.boolPreference(
            DisplayPreferenceKeys.compactInFullscreen,
            defaultValue: true
        )

        guard nextPrivacy != presentationPrivacyEnabled
                || nextHideInFullscreen != hideInFullscreenEnabled
                || nextCompactInFullscreen != compactInFullscreenEnabled else { return }

        presentationPrivacyEnabled = nextPrivacy
        hideInFullscreenEnabled = nextHideInFullscreen
        compactInFullscreenEnabled = nextCompactInFullscreen
        refreshFullscreenState()
    }

    private func scheduleFullscreenRefresh(after delay: TimeInterval) {
        fullscreenRefreshWorkItems.forEach { $0.cancel() }

        // Space/window transitions can still be animating when their first
        // notification arrives. A bounded second sample avoids permanent stale
        // state without continuously polling the relatively expensive window list.
        let firstDelay = max(0, delay)
        let delays = [firstDelay, firstDelay + Self.fullscreenRefreshRetryDelay]
        fullscreenRefreshWorkItems = delays.map { refreshDelay in
            let item = DispatchWorkItem { [weak self] in
                self?.refreshFullscreenState()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay, execute: item)
            return item
        }
    }

    private func refreshFullscreenState() {
        guard hideInFullscreenEnabled || compactInFullscreenEnabled else {
            isActiveAppFullscreen = false
            reconcileVisibility()
            return
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let isOwnAppActive = frontmostPID == ProcessInfo.processInfo.processIdentifier
        let presentationReportsFullscreen = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        let screen = targetScreen
        let displayBounds = screen.flatMap(Self.quartzDisplayBounds)
        let visibleFrameBounds: FullscreenRect?
        if let screen, let displayBounds {
            visibleFrameBounds = FullscreenCoordinateSpace.quartzVisibleFrame(
                appKitScreenFrame: Self.fullscreenRect(from: screen.frame),
                appKitVisibleFrame: Self.fullscreenRect(from: screen.visibleFrame),
                quartzDisplayBounds: displayBounds
            )
        } else {
            visibleFrameBounds = nil
        }
        let frontmostWindows: [FullscreenWindowGeometry]

        if let frontmostPID,
           !isOwnAppActive,
           !presentationReportsFullscreen,
           displayBounds != nil || visibleFrameBounds != nil {
            frontmostWindows = Self.onscreenWindows(ownedBy: frontmostPID)
        } else {
            frontmostWindows = []
        }

        isActiveAppFullscreen = ActiveAppFullscreenPolicy.isFullscreen(
            frontmostAppIsOwnApp: isOwnAppActive,
            presentationReportsFullscreen: presentationReportsFullscreen,
            targetDisplayBounds: displayBounds,
            targetVisibleFrameBounds: visibleFrameBounds,
            frontmostWindows: frontmostWindows
        )
        reconcileVisibility()
    }

    private static func quartzDisplayBounds(for screen: NSScreen) -> FullscreenRect? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }
        return fullscreenRect(
            from: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        )
    }

    private static func onscreenWindows(ownedBy processIdentifier: pid_t) -> [FullscreenWindowGeometry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { entry in
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == processIdentifier,
                  let layer = entry[kCGWindowLayer as String] as? NSNumber,
                  let alpha = entry[kCGWindowAlpha as String] as? NSNumber,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(
                      dictionaryRepresentation: boundsDictionary as CFDictionary
                  ) else {
                return nil
            }

            return FullscreenWindowGeometry(
                bounds: fullscreenRect(from: bounds),
                layer: layer.intValue,
                alpha: alpha.doubleValue
            )
        }
    }

    private static func fullscreenRect(from bounds: CGRect) -> FullscreenRect {
        FullscreenRect(
            x: Double(bounds.origin.x),
            y: Double(bounds.origin.y),
            width: Double(bounds.size.width),
            height: Double(bounds.size.height)
        )
    }

    private func reconcileVisibility() {
        let decision = OverlayVisibilityPolicy.decision(
            userWantsVisible: userWantsOverlayVisible,
            presentationPrivacyEnabled: presentationPrivacyEnabled,
            hideInFullscreenEnabled: hideInFullscreenEnabled,
            compactInFullscreenEnabled: compactInFullscreenEnabled,
            isActiveAppFullscreen: isActiveAppFullscreen
        )

        if decision.shouldCollapse, model.isExpanded {
            model.isExpanded = false
        }

        if decision.shouldShow {
            positionPanel(animated: false)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }

        updateOutsideClickMonitoring(expanded: model.isExpanded)
    }

    private var targetScreen: NSScreen? {
        if let notched = NSScreen.screens.first(where: { physicalNotchRect(on: $0) != nil }) {
            return notched
        }
        if let windowScreen = panel.screen { return windowScreen }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func updateLayout(for screen: NSScreen) {
        if let notch = physicalNotchRect(on: screen) {
            layout.update(
                hasPhysicalNotch: true,
                notchWidth: notch.width,
                notchHeight: notch.height
            )
        } else {
            layout.update(hasPhysicalNotch: false, notchWidth: 0, notchHeight: 0)
        }
    }

    private func physicalNotchRect(on screen: NSScreen) -> NSRect? {
        guard screen.safeAreaInsets.top > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return nil }

        let width = rightArea.minX - leftArea.maxX
        guard width > 20 else { return nil }
        return NSRect(
            x: leftArea.maxX,
            y: screen.frame.maxY - screen.safeAreaInsets.top,
            width: width,
            height: screen.safeAreaInsets.top
        )
    }

    private static func boolPreference(_ key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
