import Foundation

enum AlertMode: String, Codable, CaseIterable, Identifiable {
    case bpm
    case zone

    var id: String { rawValue }
    var label: String { self == .bpm ? "BPM threshold" : "Zone threshold" }
}

struct AlertConfiguration: Codable, Equatable {
    /// Enables local threshold evaluation and the amber Focus Dot state.
    /// System notification delivery is a separate user preference.
    var isEnabled = true
    var mode: AlertMode = .bpm
    var bpmThreshold = 100
    var zoneThreshold: HeartRateZone = .zone2
    var dwellSeconds: Double = 20
    var cooldownSeconds: Double = 300
    var hysteresisBPM = 5
}

enum FocusDotTone: Equatable {
    case blue
    case amber
    case unavailable
}

enum FocusDotSemanticState: Equatable {
    case normal
    case pending(progress: Double)
    case elevated(duration: TimeInterval)
    case snoozed(remaining: TimeInterval)
    case stale
    case disconnected

    var tone: FocusDotTone {
        switch self {
        case .normal, .pending:
            .blue
        case .elevated, .snoozed:
            .amber
        case .stale, .disconnected:
            .unavailable
        }
    }

    var isSustainedElevation: Bool {
        switch self {
        case .elevated, .snoozed: true
        default: false
        }
    }

    /// The attention halo is reserved for an active confirmed elevation.
    /// Snoozing keeps the amber state but quiets the glow as acknowledgement.
    var showsThresholdGlow: Bool {
        guard case .elevated = self else { return false }
        return true
    }
}

struct ThresholdEngine {
    private(set) var aboveSince: Date?
    private(set) var sustainedSince: Date?
    private(set) var cooldownUntil: Date?
    private(set) var snoozedUntil: Date?
    private(set) var hasAlertedForExcursion = false

    mutating func ingest(
        bpm: Int,
        zone: HeartRateZone,
        at date: Date,
        configuration: AlertConfiguration
    ) -> Bool {
        ingest(
            bpm: bpm,
            zone: zone,
            sensorContactDetected: nil,
            at: date,
            configuration: configuration
        )
    }

    mutating func ingest(
        bpm: Int,
        zone: HeartRateZone,
        sensorContactDetected: Bool?,
        at date: Date,
        configuration: AlertConfiguration
    ) -> Bool {
        guard sensorContactDetected != false else {
            resetExcursion()
            return false
        }
        guard configuration.isEnabled else {
            resetExcursion()
            return false
        }

        switch conditionState(bpm: bpm, zone: zone, configuration: configuration) {
        case .below:
            resetExcursion()
            return false
        case .holding:
            guard aboveSince != nil else { return false }
        case .above:
            if aboveSince == nil {
                aboveSince = date
            }
        }

        guard let aboveSince else { return false }
        if sustainedSince == nil,
           date.timeIntervalSince(aboveSince) >= max(0, configuration.dwellSeconds) {
            sustainedSince = date
        }

        guard sustainedSince != nil else { return false }

        if let snoozedUntil {
            guard date >= snoozedUntil else { return false }
            self.snoozedUntil = nil
        }

        guard !hasAlertedForExcursion,
              cooldownUntil.map({ date >= $0 }) ?? true else {
            return false
        }

        hasAlertedForExcursion = true
        cooldownUntil = date.addingTimeInterval(configuration.cooldownSeconds)
        return true
    }

    mutating func markDataStale() {
        resetExcursion()
    }

    mutating func resetElevation() {
        resetExcursion()
    }

    mutating func snooze(for duration: TimeInterval, at date: Date) {
        guard duration > 0 else {
            resumeAlerts()
            return
        }
        snoozedUntil = date.addingTimeInterval(duration)
        // Permit one new notification after both snooze and cooldown expire.
        hasAlertedForExcursion = false
    }

    mutating func resumeAlerts() {
        snoozedUntil = nil
        hasAlertedForExcursion = false
    }

    func semanticState(
        at date: Date,
        configuration: AlertConfiguration
    ) -> FocusDotSemanticState {
        guard configuration.isEnabled, let aboveSince else { return .normal }

        if sustainedSince != nil {
            if let snoozedUntil, date < snoozedUntil {
                return .snoozed(remaining: max(0, snoozedUntil.timeIntervalSince(date)))
            }
            return .elevated(duration: max(0, date.timeIntervalSince(aboveSince)))
        }

        let dwell = max(0, configuration.dwellSeconds)
        guard dwell > 0 else { return .pending(progress: 0) }
        // Confirmation still requires a fresh sample at or after the dwell boundary.
        let progress = min(0.999, max(0, date.timeIntervalSince(aboveSince) / dwell))
        return .pending(progress: progress)
    }

    private mutating func resetExcursion() {
        aboveSince = nil
        sustainedSince = nil
        snoozedUntil = nil
        hasAlertedForExcursion = false
    }

    private enum ConditionState {
        case below
        case holding
        case above
    }

    private func conditionState(
        bpm: Int,
        zone: HeartRateZone,
        configuration: AlertConfiguration
    ) -> ConditionState {
        switch configuration.mode {
        case .zone:
            return zone >= configuration.zoneThreshold ? .above : .below
        case .bpm:
            if bpm >= configuration.bpmThreshold { return .above }
            if bpm <= configuration.bpmThreshold - configuration.hysteresisBPM { return .below }
            return .holding
        }
    }
}
