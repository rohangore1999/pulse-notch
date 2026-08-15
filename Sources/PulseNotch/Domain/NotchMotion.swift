import Foundation

enum NotchPresentationTarget: Equatable, Sendable {
    case collapsed
    case expanded
}

enum NotchPresentationPhase: Equatable, Sendable {
    case collapsed
    case opening
    case open
    case closing

    var target: NotchPresentationTarget {
        switch self {
        case .collapsed, .closing:
            return .collapsed
        case .opening, .open:
            return .expanded
        }
    }

    var presentsExpandedShell: Bool {
        self != .collapsed
    }
}

struct NotchPresentationMotion: Equatable, Sendable {
    private(set) var phase: NotchPresentationPhase
    private(set) var generation: UInt

    init(initialTarget: NotchPresentationTarget = .collapsed) {
        phase = initialTarget == .expanded ? .open : .collapsed
        generation = 0
    }

    mutating func request(_ target: NotchPresentationTarget) -> UInt? {
        guard target != phase.target else { return nil }

        generation &+= 1
        phase = target == .expanded ? .opening : .closing
        return generation
    }

    func isCurrent(generation: UInt, target: NotchPresentationTarget) -> Bool {
        self.generation == generation && phase.target == target
    }

    @discardableResult
    mutating func complete(target: NotchPresentationTarget, generation: UInt) -> Bool {
        let expectedPhase: NotchPresentationPhase = target == .expanded ? .opening : .closing
        guard phase == expectedPhase, isCurrent(generation: generation, target: target) else {
            return false
        }

        phase = target == .expanded ? .open : .collapsed
        return true
    }

    mutating func snap(to target: NotchPresentationTarget) {
        let terminalPhase: NotchPresentationPhase = target == .expanded ? .open : .collapsed
        guard phase != terminalPhase else { return }

        generation &+= 1
        phase = terminalPhase
    }
}

enum NotchMotionMetrics {
    static let panelOpenDuration: TimeInterval = 0.22
    static let panelCloseDuration: TimeInterval = 0.18
    static let contentRevealDelay: TimeInterval = 0.02
    static let actionsRevealDelay: TimeInterval = 0.04
    static let closeCompletionBuffer: TimeInterval = 0

    /// Both directions redraw continuously. The view removes its expensive chart
    /// and action subtree before collapse, leaving one lightweight transition
    /// shell to resize without the frozen-backing-store pop of an end-only redraw.
    static func displaysDuringFrameAnimation(expanded _: Bool) -> Bool {
        true
    }

    /// Backdrop materials are mounted only after geometry settles. During live
    /// resize a visually matched opaque shell avoids repeatedly sampling the
    /// desktop behind the moving panel.
    static func expandedShellUsesLiveBackdrop(
        phase: NotchPresentationPhase
    ) -> Bool {
        phase == .open
    }
}

enum NotchFrameAnimationPolicy {
    static func preservesMatchingRequest(
        panelIsVisible: Bool,
        targetMatchesRequest: Bool,
        reduceMotion: Bool
    ) -> Bool {
        panelIsVisible
            && targetMatchesRequest
            && !reduceMotion
    }

    static func finishesImmediatelyForReducedMotion(
        reduceMotionEnabled: Bool,
        hasInFlightFrame: Bool
    ) -> Bool {
        reduceMotionEnabled && hasInFlightFrame
    }
}
