import Foundation

private var failureCount = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        failureCount += 1
        print("✗ \(message)")
    }
}

do {
    let eightBit = try HeartRateMeasurementParser.parse(Data([0x00, 72]))
    expect(eightBit.bpm == 72, "Parses 8-bit heart rate")

    let sixteenBit = try HeartRateMeasurementParser.parse(Data([0x01, 0x2C, 0x01]))
    expect(sixteenBit.bpm == 300, "Parses 16-bit heart rate")

    let combined = try HeartRateMeasurementParser.parse(
        Data([0x1E, 75, 0x34, 0x12, 0x00, 0x04, 0x00, 0x02])
    )
    expect(combined.sensorContactDetected == true, "Parses sensor contact")
    expect(combined.energyExpended == 0x1234, "Parses energy expended")
    expect(combined.rrIntervals == [1.0, 0.5], "Parses RR intervals")
} catch {
    failureCount += 1
    print("✗ Valid HRS packet parsing failed: \(error)")
}

let malformedPackets = [
    Data(),
    Data([0x00]),
    Data([0x01, 0x2C]),
    Data([0x08, 70, 0x01]),
    Data([0x10, 70]),
    Data([0x10, 70, 0x01]),
    Data([0x00, 70, 0x01])
]
for packet in malformedPackets {
    do {
        _ = try HeartRateMeasurementParser.parse(packet)
        failureCount += 1
        print("✗ Rejects malformed HRS packet \(Array(packet))")
    } catch {
        print("✓ Rejects malformed HRS packet \(Array(packet))")
    }
}

let deviceA = UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!
let deviceB = UUID(uuidString: "00000000-0000-0000-0000-00000000BCDE")!

expect(
    HeartRateDeviceSelectionPolicy.displayName(
        identifier: deviceA,
        peripheralName: "  Alex’s WHOOP  ",
        advertisementLocalName: "WHOOP",
        approvedDeviceID: nil,
        approvedDeviceName: nil
    ) == "Alex’s WHOOP",
    "Prefers the user-visible Bluetooth device name"
)
expect(
    HeartRateDeviceSelectionPolicy.displayName(
        identifier: deviceA,
        peripheralName: nil,
        advertisementLocalName: "WHOOP 5.0",
        approvedDeviceID: nil,
        approvedDeviceName: nil
    ) == "WHOOP 5.0",
    "Uses the advertisement name when the Bluetooth name is unavailable"
)
expect(
    HeartRateDeviceSelectionPolicy.displayName(
        identifier: deviceA,
        peripheralName: nil,
        advertisementLocalName: nil,
        approvedDeviceID: deviceA,
        approvedDeviceName: "Alex’s WHOOP"
    ) == "Alex’s WHOOP",
    "Keeps the validated device name for an approved device"
)
expect(
    HeartRateDeviceSelectionPolicy.displayName(
        identifier: deviceA,
        peripheralName: nil,
        advertisementLocalName: nil,
        approvedDeviceID: deviceB,
        approvedDeviceName: "Someone else’s device"
    ) == "Heart-rate monitor · ABCD",
    "Unnamed devices remain distinguishable by identifier"
)
expect(
    HeartRateDeviceSelectionPolicy.precedes(
        lhsID: deviceA,
        lhsName: "Weak known",
        lhsRSSI: -90,
        rhsID: deviceB,
        rhsName: "Unknown",
        rhsRSSI: HeartRateDeviceSelectionPolicy.unknownRSSI
    ),
    "Places a known signal before an unknown signal"
)
expect(
    HeartRateDeviceSelectionPolicy.precedes(
        lhsID: deviceA,
        lhsName: "Strong",
        lhsRSSI: -55,
        rhsID: deviceB,
        rhsName: "Weak",
        rhsRSSI: -90
    ),
    "Orders device rows by signal strength"
)
expect(
    !HeartRateDeviceSelectionPolicy.shouldAutomaticallyReconnect(
        candidateID: deviceA,
        approvedDeviceID: deviceA,
        isExplicitPickerScan: true
    ),
    "An explicit picker scan never auto-selects a device"
)
expect(
    HeartRateDeviceSelectionPolicy.shouldAutomaticallyReconnect(
        candidateID: deviceA,
        approvedDeviceID: deviceA,
        isExplicitPickerScan: false
    ),
    "Launch recovery reconnects only the validated device"
)
expect(
    !HeartRateDeviceSelectionPolicy.shouldAutomaticallyReconnect(
        candidateID: deviceB,
        approvedDeviceID: deviceA,
        isExplicitPickerScan: false
    ),
    "Launch recovery never substitutes another nearby monitor"
)
expect(
    HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 80),
    "A valid live BPM can approve the selected device"
)
expect(
    HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 20)
        && HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 260),
    "Live-sample approval accepts both supported BPM boundaries"
)
expect(
    !HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 19)
        && !HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 261),
    "An out-of-range packet cannot approve the selected device"
)
expect(
    HeartRateDeviceSelectionPolicy.restoredApprovedDevice(
        identifierString: deviceA.uuidString,
        name: "  Alex’s WHOOP  "
    ) == ApprovedHeartRateDeviceRecord(identifier: deviceA, name: "Alex’s WHOOP"),
    "Restores approval only from a complete validated record"
)
expect(
    HeartRateDeviceSelectionPolicy.restoredApprovedDevice(
        identifierString: deviceA.uuidString,
        name: "   "
    ) == nil
        && HeartRateDeviceSelectionPolicy.restoredApprovedDevice(
            identifierString: "not-a-uuid",
            name: "Alex’s WHOOP"
        ) == nil,
    "Rejects blank-name and malformed approval records"
)
expect(
    HeartRateDeviceSelectionPolicy.pickerScanDuration == 15,
    "Picker scans stop after a bounded discovery window"
)
expect(
    HeartRateDeviceSelectionPolicy.shouldRetryApprovedDevice(
        failedDeviceID: deviceA,
        approvedDeviceID: deviceA,
        userWantsMonitoring: true,
        bluetoothIsPoweredOn: true
    ),
    "A dropped approved device can reconnect"
)
expect(
    !HeartRateDeviceSelectionPolicy.shouldRetryApprovedDevice(
        failedDeviceID: deviceB,
        approvedDeviceID: deviceA,
        userWantsMonitoring: true,
        bluetoothIsPoweredOn: true
    ),
    "A failed unapproved device never falls back to another device"
)
expect(
    !HeartRateDeviceSelectionPolicy.shouldRetryApprovedDevice(
        failedDeviceID: deviceA,
        approvedDeviceID: deviceA,
        userWantsMonitoring: false,
        bluetoothIsPoweredOn: true
    ),
    "Manual disconnect stops approved-device retries"
)
expect(
    HeartRateDeviceSelectionPolicy.reconnectDelay(attempt: 1) == 1
        && HeartRateDeviceSelectionPolicy.reconnectDelay(attempt: 6) == 30,
    "Approved-device reconnect uses capped exponential backoff"
)
expect(
    HeartRateDeviceSelectionPolicy.shouldProcessConnectionEnd(
        isCurrentPeripheral: true,
        wasCancellation: true,
        callbackDeviceID: deviceA,
        pendingTerminationDeviceID: deviceA
    ),
    "Processes the expected cancellation callback"
)
expect(
    !HeartRateDeviceSelectionPolicy.shouldProcessConnectionEnd(
        isCurrentPeripheral: true,
        wasCancellation: true,
        callbackDeviceID: deviceA,
        pendingTerminationDeviceID: nil
    ),
    "Ignores a stale cancellation callback after switching attempts"
)

let zones = ZoneConfiguration.fromHRR(restingHeartRate: 60, maximumHeartRate: 190)
expect(zones.lowerBounds == [112, 138, 151, 164, 177], "Calculates WHOOP-style HRR bounds")
expect(zones.zone(for: 111) == .zone0, "Classifies below Z1")
expect(zones.zone(for: 112) == .zone1, "Boundary enters Z1")
expect(zones.zone(for: 177) == .zone5, "Boundary enters Z5")

var engine = ThresholdEngine()
var alerts = AlertConfiguration()
alerts.isEnabled = true
alerts.bpmThreshold = 100
alerts.dwellSeconds = 10
let start = Date(timeIntervalSince1970: 1_000)
expect(!engine.ingest(bpm: 101, zone: .zone0, at: start, configuration: alerts), "Does not alert immediately")
expect(!engine.ingest(bpm: 105, zone: .zone0, at: start.addingTimeInterval(9), configuration: alerts), "Waits for full dwell")
expect(engine.ingest(bpm: 104, zone: .zone0, at: start.addingTimeInterval(10), configuration: alerts), "Alerts after sustained threshold")
expect(!engine.ingest(bpm: 110, zone: .zone1, at: start.addingTimeInterval(20), configuration: alerts), "Alerts once per excursion")

var stateEngine = ThresholdEngine()
alerts.cooldownSeconds = 0
expect(!stateEngine.ingest(bpm: 101, zone: .zone0, at: start, configuration: alerts), "Starts elevation dwell")
let pendingState = stateEngine.semanticState(at: start.addingTimeInterval(5), configuration: alerts)
if case let .pending(progress) = pendingState {
    expect(abs(progress - 0.5) < 0.001, "Reports pending dwell progress")
    expect(pendingState.tone == .blue, "Pending elevation remains blue")
} else {
    expect(false, "Reports pending dwell progress")
}
expect(stateEngine.ingest(bpm: 103, zone: .zone0, at: start.addingTimeInterval(10), configuration: alerts), "Confirms sustained elevation")
expect(stateEngine.semanticState(at: start.addingTimeInterval(10), configuration: alerts).tone == .amber, "Sustained elevation becomes amber")

stateEngine.snooze(for: 20, at: start.addingTimeInterval(11))
let snoozedState = stateEngine.semanticState(at: start.addingTimeInterval(15), configuration: alerts)
if case let .snoozed(remaining) = snoozedState {
    expect(abs(remaining - 16) < 0.001, "Reports snooze remaining time")
    expect(snoozedState.tone == .amber, "Snoozed elevation remains amber")
} else {
    expect(false, "Reports snooze remaining time")
}
expect(!stateEngine.ingest(bpm: 105, zone: .zone0, at: start.addingTimeInterval(20), configuration: alerts), "Suppresses alerts during snooze")
expect(stateEngine.ingest(bpm: 105, zone: .zone0, at: start.addingTimeInterval(32), configuration: alerts), "Can alert after snooze expires")

stateEngine.markDataStale()
expect(stateEngine.semanticState(at: start.addingTimeInterval(32), configuration: alerts) == .normal, "Stale data resets elevation")
expect(FocusDotSemanticState.stale.tone == .unavailable, "Stale focus state is unavailable")
expect(FocusDotSemanticState.disconnected.tone == .unavailable, "Disconnected focus state is unavailable")
expect(!FocusDotSemanticState.pending(progress: 0.5).showsThresholdGlow, "Pending threshold does not glow")
expect(FocusDotSemanticState.elevated(duration: 0).showsThresholdGlow, "Confirmed elevation glows")
expect(FocusDotSemanticState.elevated(duration: 20).showsThresholdGlow, "Elevation duration ticks keep glow active")
expect(!FocusDotSemanticState.snoozed(remaining: 300).showsThresholdGlow, "Snoozing quiets threshold glow")

var contactEngine = ThresholdEngine()
expect(!contactEngine.ingest(bpm: 105, zone: .zone0, sensorContactDetected: true, at: start, configuration: alerts), "Contact reading starts dwell")
expect(!contactEngine.ingest(bpm: 110, zone: .zone0, sensorContactDetected: false, at: start.addingTimeInterval(10), configuration: alerts), "No-contact reading cannot alert")
expect(contactEngine.semanticState(at: start.addingTimeInterval(10), configuration: alerts) == .normal, "No-contact reading resets elevation")

expect(BPMThresholdInput.sanitizeDraft(" 1a2b3x4 ") == "123", "Sanitizes BPM text input")
expect(BPMThresholdInput.committedValue(from: "39", currentValue: 80) == 40, "Clamps BPM input to minimum")
expect(BPMThresholdInput.committedValue(from: "221", currentValue: 80) == 220, "Clamps BPM input to maximum")
expect(BPMThresholdInput.committedValue(from: "", currentValue: 80) == 80, "Keeps BPM after empty input")

let visibleNormally = OverlayVisibilityPolicy.decision(
    userWantsVisible: true,
    presentationPrivacyEnabled: false,
    hideInFullscreenEnabled: false,
    compactInFullscreenEnabled: true,
    isActiveAppFullscreen: false
)
expect(visibleNormally == OverlayVisibilityDecision(shouldShow: true, shouldCollapse: false), "Shows overlay outside full screen")

let hiddenForFullscreen = OverlayVisibilityPolicy.decision(
    userWantsVisible: true,
    presentationPrivacyEnabled: false,
    hideInFullscreenEnabled: true,
    compactInFullscreenEnabled: true,
    isActiveAppFullscreen: true
)
expect(hiddenForFullscreen == OverlayVisibilityDecision(shouldShow: false, shouldCollapse: true), "Hides and collapses overlay in full screen")

let restoredAfterFullscreen = OverlayVisibilityPolicy.decision(
    userWantsVisible: true,
    presentationPrivacyEnabled: false,
    hideInFullscreenEnabled: true,
    compactInFullscreenEnabled: true,
    isActiveAppFullscreen: false
)
expect(restoredAfterFullscreen.shouldShow, "Restores overlay after leaving full screen")

let manuallyHiddenAfterFullscreen = OverlayVisibilityPolicy.decision(
    userWantsVisible: false,
    presentationPrivacyEnabled: false,
    hideInFullscreenEnabled: true,
    compactInFullscreenEnabled: true,
    isActiveAppFullscreen: false
)
expect(!manuallyHiddenAfterFullscreen.shouldShow, "Manual hide survives full-screen transitions")

let privacyWins = OverlayVisibilityPolicy.decision(
    userWantsVisible: true,
    presentationPrivacyEnabled: true,
    hideInFullscreenEnabled: false,
    compactInFullscreenEnabled: false,
    isActiveAppFullscreen: false
)
expect(!privacyWins.shouldShow, "Presentation privacy always hides overlay")

for isExpanded in [false, true] {
    for overlayIsVisible in [false, true] {
        for userWantsOverlayVisible in [false, true] {
            for clickIsInsideOverlay in [false, true] {
                let expected = isExpanded
                    && overlayIsVisible
                    && userWantsOverlayVisible
                    && !clickIsInsideOverlay
                let actual = OutsideClickDismissalPolicy.shouldCollapse(
                    isExpanded: isExpanded,
                    overlayIsVisible: overlayIsVisible,
                    userWantsOverlayVisible: userWantsOverlayVisible,
                    clickIsInsideOverlay: clickIsInsideOverlay
                )
                expect(
                    actual == expected,
                    "Outside-click dismissal matrix: expanded=\(isExpanded), visible=\(overlayIsVisible), userVisible=\(userWantsOverlayVisible), inside=\(clickIsInsideOverlay)"
                )
            }
        }
    }
}

let fullscreenDisplay = FullscreenRect(x: 0, y: 0, width: 1_800, height: 1_169)
let fullscreenVisibleFrame = FullscreenRect(x: 0, y: 39, width: 1_800, height: 1_130)
let screenCoveringWindow = FullscreenWindowGeometry(
    bounds: fullscreenDisplay,
    layer: 0,
    alpha: 1
)
expect(
    ActiveAppFullscreenPolicy.isFullscreen(
        frontmostAppIsOwnApp: false,
        presentationReportsFullscreen: false,
        targetDisplayBounds: fullscreenDisplay,
        targetVisibleFrameBounds: fullscreenVisibleFrame,
        frontmostWindows: [screenCoveringWindow]
    ),
    "Detects a screen-covering custom full-screen window"
)
expect(
    ActiveAppFullscreenPolicy.isFullscreen(
        frontmostAppIsOwnApp: false,
        presentationReportsFullscreen: true,
        targetDisplayBounds: nil,
        targetVisibleFrameBounds: nil,
        frontmostWindows: []
    ),
    "Trusts AppKit's native full-screen presentation signal"
)
expect(
    !ActiveAppFullscreenPolicy.isFullscreen(
        frontmostAppIsOwnApp: true,
        presentationReportsFullscreen: true,
        targetDisplayBounds: fullscreenDisplay,
        targetVisibleFrameBounds: fullscreenVisibleFrame,
        frontmostWindows: [screenCoveringWindow]
    ),
    "Does not treat Pulse Notch itself as the full-screen foreground app"
)

let screenshotVisibleFrameWindow = FullscreenWindowGeometry(
    bounds: fullscreenVisibleFrame,
    layer: 0,
    alpha: 1
)
expect(
    ActiveAppFullscreenPolicy.isFullscreen(
        frontmostAppIsOwnApp: false,
        presentationReportsFullscreen: false,
        targetDisplayBounds: fullscreenDisplay,
        targetVisibleFrameBounds: fullscreenVisibleFrame,
        frontmostWindows: [screenshotVisibleFrameWindow]
    ),
    "Detects the screenshot's visible-frame-filling ChatGPT window"
)

let ordinaryInsetWindow = FullscreenWindowGeometry(
    bounds: FullscreenRect(x: 20, y: 60, width: 1_760, height: 1_070),
    layer: 0,
    alpha: 1
)
expect(
    !ActiveAppFullscreenPolicy.isFullscreen(
        frontmostAppIsOwnApp: false,
        presentationReportsFullscreen: false,
        targetDisplayBounds: fullscreenDisplay,
        targetVisibleFrameBounds: fullscreenVisibleFrame,
        frontmostWindows: [ordinaryInsetWindow]
    ),
    "Does not mistake an ordinary window inset within the visible frame for full screen"
)

let fullScreenHelperWindow = FullscreenWindowGeometry(
    bounds: fullscreenDisplay,
    layer: 3,
    alpha: 1
)
expect(
    !ActiveAppFullscreenPolicy.isFullscreen(
        frontmostAppIsOwnApp: false,
        presentationReportsFullscreen: false,
        targetDisplayBounds: fullscreenDisplay,
        targetVisibleFrameBounds: fullscreenVisibleFrame,
        frontmostWindows: [fullScreenHelperWindow]
    ),
    "Ignores screen-sized helper windows above the normal application layer"
)

let roundedFullscreenWindow = FullscreenWindowGeometry(
    bounds: FullscreenRect(x: 1, y: 1, width: 1_798, height: 1_167),
    layer: 0,
    alpha: 1
)
expect(
    ActiveAppFullscreenPolicy.isFullscreen(
        frontmostAppIsOwnApp: false,
        presentationReportsFullscreen: false,
        targetDisplayBounds: fullscreenDisplay,
        targetVisibleFrameBounds: fullscreenVisibleFrame,
        frontmostWindows: [roundedFullscreenWindow]
    ),
    "Allows small Quartz coordinate rounding at display edges"
)

let convertedVisibleFrame = FullscreenCoordinateSpace.quartzVisibleFrame(
    appKitScreenFrame: FullscreenRect(x: -900, y: 200, width: 900, height: 584.5),
    appKitVisibleFrame: FullscreenRect(x: -900, y: 200, width: 900, height: 565),
    quartzDisplayBounds: FullscreenRect(x: 3_600, y: 100, width: 1_800, height: 1_169)
)
expect(
    convertedVisibleFrame == FullscreenRect(x: 3_600, y: 139, width: 1_800, height: 1_130),
    "Converts a scaled non-primary AppKit visible frame into Quartz coordinates"
)

do {
    var motion = NotchPresentationMotion(initialTarget: .expanded)
    let closeGeneration = motion.request(.collapsed)

    expect(closeGeneration == 1, "A close creates one target generation")
    expect(motion.phase == .closing, "A close request enters the closing phase")
    expect(motion.phase.target == .collapsed, "Closing targets the collapsed presentation")
    expect(motion.phase.presentsExpandedShell, "Closing keeps the expanded shell present")
    expect(motion.request(.collapsed) == nil, "A repeated close does not create another target change")
    expect(motion.generation == closeGeneration, "A repeated close preserves the current generation")
    expect(
        motion.complete(target: .collapsed, generation: closeGeneration!),
        "The current close completion is accepted"
    )
    expect(motion.phase == .collapsed, "A completed close reaches the collapsed phase")
    expect(!motion.phase.presentsExpandedShell, "A completed close removes the expanded shell")
    expect(
        !motion.complete(target: .collapsed, generation: closeGeneration!),
        "A close completion changes phase only once"
    )
}

do {
    var motion = NotchPresentationMotion()

    expect(motion.request(.collapsed) == nil, "A duplicate settled target is idempotent")
    expect(motion.generation == 0, "A duplicate settled target does not advance generation")

    let openGeneration = motion.request(.expanded)
    expect(openGeneration == 1, "An open request advances generation once")
    expect(motion.request(.expanded) == nil, "A duplicate in-flight target is idempotent")
    expect(motion.generation == openGeneration, "A duplicate in-flight target preserves generation")
}

do {
    var motion = NotchPresentationMotion()
    let openGeneration = motion.request(.expanded)!
    let closeGeneration = motion.request(.collapsed)!

    expect(
        !motion.complete(target: .expanded, generation: openGeneration),
        "A stale open completion is rejected after reversal"
    )
    expect(motion.phase == .closing, "A stale completion does not replace the reversed phase")
    expect(
        motion.complete(target: .collapsed, generation: closeGeneration),
        "The completion for the reversed target is accepted"
    )
}

do {
    var motion = NotchPresentationMotion()
    let firstOpenGeneration = motion.request(.expanded)!
    let closeGeneration = motion.request(.collapsed)!
    let finalOpenGeneration = motion.request(.expanded)!

    expect(finalOpenGeneration > closeGeneration, "Each reversal records a newer intent")
    expect(
        !motion.complete(target: .collapsed, generation: closeGeneration),
        "A superseded close cannot override the final intent"
    )
    expect(
        !motion.complete(target: .expanded, generation: firstOpenGeneration),
        "An earlier open cannot complete the final intent"
    )
    expect(
        motion.complete(target: .expanded, generation: finalOpenGeneration),
        "The last presentation intent wins"
    )
    expect(motion.phase == .open, "The last open intent reaches the open phase")
}

do {
    var motion = NotchPresentationMotion()
    let animatedGeneration = motion.request(.expanded)!

    motion.snap(to: .expanded)
    expect(motion.phase == .open, "Reduce motion snaps directly to the open phase")
    expect(motion.generation > animatedGeneration, "Snapping invalidates an in-flight animation")
    expect(
        !motion.complete(target: .expanded, generation: animatedGeneration),
        "A snapped animation cannot complete later"
    )

    motion.snap(to: .collapsed)
    expect(motion.phase == .collapsed, "Reduce motion snaps directly to the collapsed phase")
    let settledGeneration = motion.generation
    motion.snap(to: .collapsed)
    expect(motion.generation == settledGeneration, "Snapping to a settled target is idempotent")
}

expect(NotchMotionMetrics.panelOpenDuration == 0.22, "Uses the panel open duration")
expect(NotchMotionMetrics.panelCloseDuration == 0.18, "Uses the panel close duration")
expect(NotchMotionMetrics.contentRevealDelay == 0.02, "Uses the content reveal delay")
expect(NotchMotionMetrics.actionsRevealDelay == 0.04, "Uses the actions reveal delay")
expect(NotchMotionMetrics.closeCompletionBuffer == 0, "Close completion has no delayed terminal tail")
expect(
    NotchMotionMetrics.displaysDuringFrameAnimation(expanded: true),
    "Opening redraws as the panel grows"
)
expect(
    NotchMotionMetrics.displaysDuringFrameAnimation(expanded: false),
    "Closing redraws the lightweight shell continuously without a terminal pop"
)
expect(
    !NotchMotionMetrics.expandedShellUsesLiveBackdrop(phase: .opening),
    "Opening resizes a lightweight shell instead of a live backdrop"
)
expect(
    NotchMotionMetrics.expandedShellUsesLiveBackdrop(phase: .open),
    "The settled detail panel restores its live backdrop"
)
expect(
    !NotchMotionMetrics.expandedShellUsesLiveBackdrop(phase: .closing),
    "Closing does not resize a live backdrop"
)
expect(
    NotchFrameAnimationPolicy.preservesMatchingRequest(
        panelIsVisible: true,
        targetMatchesRequest: true,
        reduceMotion: false
    ),
    "A normal visibility refresh preserves the matching in-flight frame animation"
)
expect(
    !NotchFrameAnimationPolicy.preservesMatchingRequest(
        panelIsVisible: true,
        targetMatchesRequest: true,
        reduceMotion: true
    ),
    "Reduce Motion can interrupt a matching in-flight frame animation"
)
expect(
    NotchFrameAnimationPolicy.finishesImmediatelyForReducedMotion(
        reduceMotionEnabled: true,
        hasInFlightFrame: true
    ),
    "Enabling Reduce Motion finishes an in-flight panel frame immediately"
)
expect(
    !NotchFrameAnimationPolicy.finishesImmediatelyForReducedMotion(
        reduceMotionEnabled: false,
        hasInFlightFrame: true
    ),
    "Other accessibility display changes preserve an in-flight panel frame"
)
expect(
    !NotchFrameAnimationPolicy.finishesImmediatelyForReducedMotion(
        reduceMotionEnabled: true,
        hasInFlightFrame: false
    ),
    "Reduce Motion does not create frame work when no panel animation is active"
)
expect(
    NotchFrameAnimationPolicy.preservesMatchingRequest(
        panelIsVisible: true,
        targetMatchesRequest: true,
        reduceMotion: false
    ),
    "Full-screen compaction preserves the matching close animation"
)
expect(
    !NotchFrameAnimationPolicy.preservesMatchingRequest(
        panelIsVisible: false,
        targetMatchesRequest: true,
        reduceMotion: false
    ),
    "A hidden panel can be positioned exactly before it is shown again"
)
let revealDelays = [
    NotchMotionMetrics.contentRevealDelay,
    NotchMotionMetrics.actionsRevealDelay
]
expect(
    revealDelays.allSatisfy { $0 >= 0 && $0 <= NotchMotionMetrics.panelOpenDuration },
    "All reveal delays fit inside the panel open duration"
)
expect(
    revealDelays.reduce(0, +) <= NotchMotionMetrics.panelOpenDuration,
    "Sequential reveal delays finish inside the panel open duration"
)

if failureCount > 0 {
    print("\n\(failureCount) local test(s) failed")
    exit(1)
}

print("\nAll local tests passed")
