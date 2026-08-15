import Combine
import SwiftUI

struct NotchPillView: View {
    @ObservedObject var model: HeartRateAppModel
    @ObservedObject var layout: NotchLayoutState
    let openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("pulseNotch.defaultSnoozeMinutes.v1") private var defaultSnoozeMinutes = 15
    @State private var resetPresentation: ResetPresentation = .none
    @State private var resetSecondsRemaining = 60
    @State private var expansionStage: ExpansionStage = .collapsed
    @State private var expansionTask: Task<Void, Never>?
    @State private var presentationMotion = NotchPresentationMotion()

    private let secondTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let expandedContentTopPadding: CGFloat = 14
    private let expandedShellBottomInset: CGFloat = 6

    private var zone: HeartRateZone? { model.currentZone }

    private var accent: Color {
        switch model.focusState {
        case .elevated, .snoozed:
            FocusDotTheme.elevated
        case .stale, .disconnected:
            FocusDotTheme.unavailable
        case .normal, .pending:
            FocusDotTheme.live
        }
    }

    private var isElevated: Bool {
        switch model.focusState {
        case .elevated, .snoozed: true
        default: false
        }
    }

    private var isThresholdGlowActive: Bool {
        model.focusState.showsThresholdGlow
    }

    private var isMotionSettled: Bool {
        presentationMotion.phase == .collapsed || presentationMotion.phase == .open
    }

    private var rendersThresholdGlow: Bool {
        isThresholdGlowActive && isMotionSettled
    }

    private var pendingProgress: Double? {
        guard case let .pending(progress) = model.focusState else { return nil }
        return progress
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleExpanded) {
                if layout.hasPhysicalNotch {
                    notchedHeader
                } else {
                    fallbackHeader
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor(presentationMotion.phase.presentsExpandedShell)

            if presentationMotion.phase.presentsExpandedShell,
               expansionStage.revealsContent {
                expandedContent
                    .frame(
                        width: expandedContentWidth,
                        height: expandedContentHeight,
                        alignment: .top
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, expandedContentTopPadding)
                    .allowsHitTesting(
                        expansionStage.revealsContent
                            && presentationMotion.phase != .closing
                    )
                    .transition(
                        reduceMotion
                            ? .identity
                            : .opacity.combined(with: .offset(y: -3))
                    )
            }
        }
        .frame(
            width: layout.panelSize(expanded: presentationMotion.phase.presentsExpandedShell).width,
            height: layout.panelSize(expanded: presentationMotion.phase.presentsExpandedShell).height,
            alignment: .top
        )
        .background(containerBackground)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.24), value: accent)
        .onReceive(secondTick) { _ in tickReset() }
        .onAppear {
            configurePreviewStateIfNeeded()
            synchronizeExpansion(with: model.isExpanded)
        }
        .onChange(of: model.isExpanded) { expanded in
            synchronizeExpansion(with: expanded)
        }
        .onChange(of: reduceMotion) { _ in
            synchronizeMotionPreference()
        }
        .onDisappear {
            expansionTask?.cancel()
        }
    }

    private var expandedContentWidth: CGFloat {
        layout.panelSize(expanded: true).width - 28
    }

    private var expandedContentHeight: CGFloat {
        let headerHeight = layout.hasPhysicalNotch ? layout.notchHeight : layout.fallbackHeight
        return max(
            0,
            layout.expandedHeight
                - headerHeight
                - expandedContentTopPadding
                - expandedShellBottomInset
        )
    }

    private var notchedHeader: some View {
        HStack(spacing: 0) {
            compactLeading
                .frame(width: layout.compactWingWidth, height: layout.notchHeight)
                .background(compactWingBackground)

            Color.clear
                .frame(width: layout.notchWidth, height: layout.notchHeight)
                .accessibilityHidden(true)

            compactTrailing
                .frame(width: layout.compactWingWidth, height: layout.notchHeight)
                .background(compactWingBackground)
        }
        .frame(width: layout.collapsedWidth, height: layout.collapsedHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var fallbackHeader: some View {
        HStack(spacing: 0) {
            compactLeading
                .frame(width: 152, height: layout.fallbackHeight)
            Spacer(minLength: 8)
            compactTrailing
                .frame(width: 184, height: layout.fallbackHeight)
        }
        .padding(.horizontal, 8)
        .frame(width: layout.fallbackWidth, height: layout.fallbackHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var compactLeading: some View {
        HStack(spacing: 7) {
            focusGlyph

            Text(model.bpm.map(String.init) ?? "—")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(FocusDotTheme.textPrimary)
                .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: model.bpm)

            Text("BPM")
                .font(.system(size: 9, weight: .medium))
                .tracking(0.35)
                .foregroundStyle(FocusDotTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var compactTrailing: some View {
        HStack(spacing: 8) {
            Text(zone?.shortName ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)

            SparklineView(
                samples: model.samples,
                minimumBPM: chartMinimum,
                maximumBPM: chartMaximum,
                isStale: model.isStale,
                accent: accent,
                style: .compact,
                window: 60
            )
            .frame(width: 68, height: 18)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var focusGlyph: some View {
        ZStack {
            if let pendingProgress {
                Circle()
                    .stroke(accent.opacity(0.24), lineWidth: 1.4)
                    .frame(width: 23, height: 23)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, pendingProgress)))
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 23, height: 23)
            }

            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
        }
        .frame(width: 24, height: 24)
    }

    private var wingBackground: some View {
        AdaptiveGlassSurface(
            cornerRadius: 13,
            tint: accent,
            tintOpacity: isElevated ? 0.028 : 0.025,
            isInteractive: true
        )
        .overlay { statusBorder(cornerRadius: 13) }
        .shadow(color: accent.opacity(rendersThresholdGlow ? 0.20 : 0), radius: 10)
    }

    @ViewBuilder
    private var compactWingBackground: some View {
        if presentationMotion.phase.presentsExpandedShell {
            Color.clear
        } else {
            wingBackground
        }
    }

    private func statusBorder(cornerRadius: CGFloat) -> some View {
        ZStack {
            if rendersThresholdGlow {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FocusDotTheme.elevated.opacity(0.18), lineWidth: 3)
                    .blur(radius: 4.2)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isElevated
                        ? FocusDotTheme.elevatedHighlight.opacity(rendersThresholdGlow ? 0.46 : 0.32)
                        : Color.white.opacity(0.035),
                    lineWidth: isElevated ? 0.75 : 1
                )
        }
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.24), value: rendersThresholdGlow)
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch resetPresentation {
        case .none:
            monitoringContent
        case .active:
            VStack(spacing: 8) {
                BreathingResetView(
                    secondsRemaining: resetSecondsRemaining,
                    accent: FocusDotTheme.live,
                    stop: stopReset
                )
                footer
            }
            .padding(.bottom, 8)
        case .completeInRange:
            resetCompletionContent(inRange: true)
        case .completeElevated:
            resetCompletionContent(inRange: false)
        }
    }

    private var monitoringContent: some View {
        VStack(spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusHeadline)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isElevated ? accent : FocusDotTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("Threshold: \(thresholdBPM)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(FocusDotTheme.textSecondary)
                    .lineLimit(1)
                    .accessibilityLabel("Alert threshold \(thresholdBPM) beats per minute")
            }

            VStack(spacing: 2) {
                SparklineView(
                    samples: model.samples,
                    minimumBPM: chartMinimum,
                    maximumBPM: chartMaximum,
                    isStale: model.isStale,
                    thresholdBPM: thresholdBPM,
                    accent: accent,
                    style: .expanded,
                    window: 180
                )
                .frame(height: isElevated ? 56 : 78)

                HStack {
                    Text("3:00")
                    Spacer()
                    Text("1:30")
                    Spacer()
                    Text("Now")
                }
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(FocusDotTheme.textSecondary)
            }

            monitoringActionsSlot
        }
    }

    private var monitoringActionsSlot: some View {
        Color.clear
            .frame(height: isElevated ? 134 : 108)
            .overlay(alignment: .top) {
                if expansionStage.revealsActions {
                    monitoringActions
                        .transition(
                            reduceMotion
                                ? .identity
                                : .opacity.combined(with: .offset(y: 7))
                        )
                }
            }
            .allowsHitTesting(
                expansionStage.revealsActions
                    && presentationMotion.phase != .closing
            )
    }

    private var monitoringActions: some View {
        VStack(spacing: 11) {
            Button(action: startReset) {
                Label("Start 60-second reset", systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FocusDotActionButtonStyle(.primary, tint: isElevated ? FocusDotTheme.elevated : FocusDotTheme.live))

            HStack(spacing: 8) {
                if case .snoozed = model.focusState {
                    Button(action: model.resumeAlerts) {
                        Label("Resume alerts", systemImage: "bell.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FocusDotActionButtonStyle(.secondary))
                } else {
                    Button {
                        model.snoozeAlerts(for: TimeInterval(defaultSnoozeMinutes * 60))
                    } label: {
                        Label("Snooze \(defaultSnoozeMinutes) min", systemImage: "bell")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FocusDotActionButtonStyle(.secondary))
                }

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("Settings")
                }
                .buttonStyle(FocusDotIconButtonStyle())
            }

            monitoringFooter
        }
    }

    @ViewBuilder
    private var monitoringFooter: some View {
        if isElevated {
            VStack(spacing: 11) {
                Button("Dismiss") {
                    model.resetElevation()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FocusDotTheme.elevated)
                .frame(height: 14)
                .pointingHandCursor()

                footer
            }
        } else {
            footer
        }
    }

    private func resetCompletionContent(inRange: Bool) -> some View {
        VStack(spacing: 13) {
            Spacer(minLength: 0)

            Image(systemName: inRange ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 31, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(inRange ? FocusDotTheme.live : FocusDotTheme.textSecondary)

            VStack(spacing: 4) {
                Text(inRange ? "Back within your threshold" : "Reset complete")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FocusDotTheme.textPrimary)
                Text(inRange ? "Your live reading has settled." : "Take another moment if useful.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(FocusDotTheme.textSecondary)
            }

            HStack(spacing: 8) {
                if !inRange {
                    Button("Repeat", action: startReset)
                        .buttonStyle(FocusDotActionButtonStyle(.primary, tint: FocusDotTheme.live))
                }
                Button(inRange ? "Done" : "Dismiss", action: dismissReset)
                    .buttonStyle(FocusDotActionButtonStyle(inRange ? .primary : .secondary, tint: FocusDotTheme.live))
            }

            Spacer(minLength: 0)

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Text("WHOOP 5.0")
            Text("·")
            Text(model.isSimulating ? "Demo" : "Live BLE")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(FocusDotTheme.textTertiary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var containerBackground: some View {
        if layout.hasPhysicalNotch {
            ZStack(alignment: .top) {
                if presentationMotion.phase.presentsExpandedShell {
                    glassPanelSurface(cornerRadius: 20)
                        .frame(
                            width: layout.panelSize(expanded: true).width,
                            height: layout.expandedHeight - expandedShellBottomInset
                        )
                }

                cameraCutoutBackground
            }
        } else {
            if presentationMotion.phase.presentsExpandedShell {
                glassPanelSurface(cornerRadius: 20)
                    .frame(
                        width: layout.panelSize(expanded: true).width,
                        height: layout.expandedHeight - expandedShellBottomInset
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(FocusDotTheme.notch)
                    .overlay { statusBorder(cornerRadius: 13) }
                    .shadow(color: .black.opacity(0.30), radius: 10, y: 4)
            }
        }
    }

    private func glassPanelSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            if NotchMotionMetrics.expandedShellUsesLiveBackdrop(
                phase: presentationMotion.phase
            ) {
                AdaptiveGlassSurface(
                    cornerRadius: cornerRadius,
                    tint: accent,
                    tintOpacity: isElevated ? 0.014 : 0.012,
                    reflectionIntensity: 0.55
                )
            } else {
                shape.fill(FocusDotTheme.panel)
                shape.fill(accent.opacity(isElevated ? 0.028 : 0.014))
            }
            shape
                .inset(by: 1)
                .strokeBorder(FocusDotTheme.glassInnerEdge, lineWidth: 0.5)
            statusBorder(cornerRadius: cornerRadius)
        }
        .shadow(
            color: .black.opacity(isMotionSettled ? 0.28 : 0.16),
            radius: isMotionSettled ? 16 : 8,
            y: isMotionSettled ? 7 : 3
        )
        .shadow(
            color: rendersThresholdGlow ? FocusDotTheme.elevated.opacity(0.10) : .clear,
            radius: 10
        )
    }

    private var cameraCutoutBackground: some View {
        let cornerRadius: CGFloat = 13
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(FocusDotTheme.notch)
            .frame(
                width: layout.notchWidth,
                height: layout.notchHeight + cornerRadius
            )
            .offset(y: -cornerRadius)
    }

    private var thresholdBPM: Int {
        switch model.settings.alerts.mode {
        case .bpm:
            return model.settings.alerts.bpmThreshold
        case .zone:
            let zone = model.settings.alerts.zoneThreshold
            guard zone.rawValue > 0 else { return model.settings.zones.restingHeartRate }
            let index = min(model.settings.zones.lowerBounds.count - 1, zone.rawValue - 1)
            return model.settings.zones.lowerBounds[index]
        }
    }

    private var chartMinimum: Int {
        let sampleMinimum = model.samples.map(\.bpm).min() ?? (thresholdBPM - 35)
        return max(30, min(sampleMinimum - 8, thresholdBPM - 35))
    }

    private var chartMaximum: Int {
        let sampleMaximum = model.samples.map(\.bpm).max() ?? (thresholdBPM + 12)
        return max(sampleMaximum + 8, thresholdBPM + 12)
    }

    private var statusHeadline: String {
        switch model.focusState {
        case .normal:
            return "Within your threshold"
        case let .pending(progress):
            let remaining = max(0, Int(ceil(model.settings.alerts.dwellSeconds * (1 - progress))))
            return "Elevated · checking for \(remaining)s"
        case let .elevated(duration):
            return "Elevated for \(durationText(duration))"
        case let .snoozed(remaining):
            return "Alerts snoozed for \(shortDuration(remaining))"
        case .stale:
            return "Waiting for a fresh reading"
        case .disconnected:
            return "Connect WHOOP to begin"
        }
    }

    private var accessibilitySummary: String {
        guard let bpm = model.bpm else { return "No live heart-rate reading. \(model.connectionStatus.text)" }
        let freshness = model.isStale ? "stale" : "live"
        return "\(bpm) beats per minute, \(zone?.shortName ?? "no zone"), \(freshness)"
    }

    private func toggleExpanded() {
        if presentationMotion.phase.target == .collapsed {
            beginOpenSequence()
        } else {
            beginCollapseSequence()
        }
    }

    private func synchronizeExpansion(with expanded: Bool) {
        if reduceMotion {
            expansionTask?.cancel()
            let target: NotchPresentationTarget = expanded ? .expanded : .collapsed
            presentationMotion.snap(to: target)
            expansionStage = expanded ? .actions : .collapsed
            return
        }

        let target: NotchPresentationTarget = expanded ? .expanded : .collapsed
        guard presentationMotion.phase.target != target else { return }

        if expanded {
            beginOpenSequence()
        } else {
            beginCollapseSequence()
        }
    }

    private func beginOpenSequence() {
        expansionTask?.cancel()

        guard let generation = presentationMotion.request(.expanded) else { return }

        guard !reduceMotion else {
            presentationMotion.snap(to: .expanded)
            expansionStage = .actions
            if !model.isExpanded { model.isExpanded = true }
            return
        }

        expansionStage = .shell
        if !model.isExpanded { model.isExpanded = true }

        expansionTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: nanoseconds(NotchMotionMetrics.contentRevealDelay)
            )

            guard !Task.isCancelled,
                  presentationMotion.isCurrent(generation: generation, target: .expanded) else { return }

            withAnimation(.focusDotContentOpen) {
                expansionStage = .content
            }

            try? await Task.sleep(
                nanoseconds: nanoseconds(NotchMotionMetrics.actionsRevealDelay)
            )

            guard !Task.isCancelled,
                  presentationMotion.isCurrent(generation: generation, target: .expanded) else { return }

            withAnimation(.focusDotActionsOpen) {
                expansionStage = .actions
            }

            let settleDelay = max(
                0,
                NotchMotionMetrics.panelOpenDuration
                    - NotchMotionMetrics.contentRevealDelay
                    - NotchMotionMetrics.actionsRevealDelay
            )
            try? await Task.sleep(nanoseconds: nanoseconds(settleDelay))

            guard !Task.isCancelled else { return }
            _ = presentationMotion.complete(target: .expanded, generation: generation)
        }
    }

    private func beginCollapseSequence() {
        expansionTask?.cancel()

        guard let generation = presentationMotion.request(.collapsed) else { return }

        guard !reduceMotion else {
            presentationMotion.snap(to: .collapsed)
            expansionStage = .collapsed
            if model.isExpanded { model.isExpanded = false }
            return
        }

        // Remove the chart and nested glass controls before the NSPanel begins
        // resizing. The shell morph is the close feedback; retaining an opacity
        // transition here keeps the expensive subtree alive for most of it.
        expansionStage = .shell
        if model.isExpanded { model.isExpanded = false }

        expansionTask = Task { @MainActor in
            let completionDelay = NotchMotionMetrics.panelCloseDuration
                + NotchMotionMetrics.closeCompletionBuffer
            try? await Task.sleep(nanoseconds: nanoseconds(completionDelay))

            guard !Task.isCancelled,
                  presentationMotion.isCurrent(generation: generation, target: .collapsed) else { return }
            expansionStage = .collapsed
            _ = presentationMotion.complete(target: .collapsed, generation: generation)
        }
    }

    private func synchronizeMotionPreference() {
        expansionTask?.cancel()

        guard reduceMotion else {
            synchronizeExpansion(with: model.isExpanded)
            return
        }

        let target: NotchPresentationTarget = model.isExpanded ? .expanded : .collapsed
        presentationMotion.snap(to: target)
        expansionStage = model.isExpanded ? .actions : .collapsed
    }

    private func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }

    private func startReset() {
        resetSecondsRemaining = 60
        resetPresentation = .active
    }

    private func stopReset() {
        resetPresentation = .none
        resetSecondsRemaining = 60
    }

    private func dismissReset() {
        resetPresentation = .none
        resetSecondsRemaining = 60
        model.resetElevation()
    }

    private func tickReset() {
        guard resetPresentation == .active else { return }
        if resetSecondsRemaining > 1 {
            resetSecondsRemaining -= 1
        } else {
            resetSecondsRemaining = 0
            resetPresentation = isElevated ? .completeElevated : .completeInRange
        }
    }

    private func configurePreviewStateIfNeeded() {
        switch ProcessInfo.processInfo.environment["PULSE_NOTCH_CAPTURE_STATE"] {
        case "reset":
            resetSecondsRemaining = 42
            resetPresentation = .active
        case "complete":
            resetPresentation = .completeInRange
        default:
            break
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let minutes = total / 60
        let remainder = total % 60
        return minutes > 0 ? "\(minutes) min \(remainder) sec" : "\(remainder) sec"
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 60 { return "\(total / 60)m" }
        return "\(total)s"
    }
}

private enum ResetPresentation: Equatable {
    case none
    case active
    case completeInRange
    case completeElevated
}

private enum ExpansionStage: Int {
    case collapsed
    case shell
    case content
    case actions

    var revealsShell: Bool { rawValue >= Self.shell.rawValue }
    var revealsContent: Bool { rawValue >= Self.content.rawValue }
    var revealsActions: Bool { rawValue >= Self.actions.rawValue }
}
