import Foundation
import XCTest
@testable import PulseNotch

final class ThresholdEngineTests: XCTestCase {
    func testRequiresSustainedBPMBeforeAlerting() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.bpmThreshold = 100
        configuration.dwellSeconds = 10
        configuration.cooldownSeconds = 60

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(engine.ingest(bpm: 101, zone: .zone0, at: start, configuration: configuration))
        XCTAssertFalse(engine.ingest(bpm: 105, zone: .zone0, at: start.addingTimeInterval(9), configuration: configuration))
        XCTAssertTrue(engine.ingest(bpm: 104, zone: .zone0, at: start.addingTimeInterval(10), configuration: configuration))
        XCTAssertFalse(engine.ingest(bpm: 110, zone: .zone1, at: start.addingTimeInterval(30), configuration: configuration))
    }

    func testHysteresisPreventsBoundaryFlapping() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.bpmThreshold = 100
        configuration.hysteresisBPM = 5
        configuration.dwellSeconds = 10

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(engine.ingest(bpm: 100, zone: .zone0, at: start, configuration: configuration))
        XCTAssertFalse(engine.ingest(bpm: 98, zone: .zone0, at: start.addingTimeInterval(5), configuration: configuration))
        XCTAssertTrue(engine.ingest(bpm: 101, zone: .zone0, at: start.addingTimeInterval(10), configuration: configuration))
    }

    func testZoneThresholdAndStaleReset() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.mode = .zone
        configuration.zoneThreshold = .zone2
        configuration.dwellSeconds = 5

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(engine.ingest(bpm: 140, zone: .zone2, at: start, configuration: configuration))
        engine.markDataStale()
        XCTAssertFalse(engine.ingest(bpm: 145, zone: .zone2, at: start.addingTimeInterval(6), configuration: configuration))
        XCTAssertTrue(engine.ingest(bpm: 145, zone: .zone2, at: start.addingTimeInterval(11), configuration: configuration))
    }

    func testPendingRemainsBlueUntilDwellCompletes() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.bpmThreshold = 100
        configuration.dwellSeconds = 10

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(engine.ingest(bpm: 101, zone: .zone0, at: start, configuration: configuration))

        guard case let .pending(progress) = engine.semanticState(
            at: start.addingTimeInterval(5),
            configuration: configuration
        ) else {
            return XCTFail("Expected pending state before dwell completion")
        }
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(FocusDotSemanticState.pending(progress: progress).tone, .blue)

        XCTAssertTrue(engine.ingest(
            bpm: 104,
            zone: .zone0,
            at: start.addingTimeInterval(10),
            configuration: configuration
        ))
        guard case let .elevated(duration) = engine.semanticState(
            at: start.addingTimeInterval(10),
            configuration: configuration
        ) else {
            return XCTFail("Expected elevated state after dwell completion")
        }
        XCTAssertEqual(duration, 10, accuracy: 0.001)
        XCTAssertEqual(FocusDotSemanticState.elevated(duration: duration).tone, .amber)
    }

    func testSustainedElevationUsesHysteresisBeforeResetting() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.bpmThreshold = 100
        configuration.hysteresisBPM = 5
        configuration.dwellSeconds = 5

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(engine.ingest(bpm: 101, zone: .zone0, at: start, configuration: configuration))
        XCTAssertTrue(engine.ingest(bpm: 103, zone: .zone0, at: start.addingTimeInterval(5), configuration: configuration))

        XCTAssertFalse(engine.ingest(bpm: 98, zone: .zone0, at: start.addingTimeInterval(6), configuration: configuration))
        XCTAssertTrue(engine.semanticState(
            at: start.addingTimeInterval(6),
            configuration: configuration
        ).isSustainedElevation)

        XCTAssertFalse(engine.ingest(bpm: 95, zone: .zone0, at: start.addingTimeInterval(7), configuration: configuration))
        XCTAssertEqual(engine.semanticState(
            at: start.addingTimeInterval(7),
            configuration: configuration
        ), .normal)
    }

    func testSnoozeKeepsAmberStateAndSuppressesAlertsUntilExpiry() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.bpmThreshold = 100
        configuration.dwellSeconds = 5
        configuration.cooldownSeconds = 0

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(engine.ingest(bpm: 101, zone: .zone0, at: start, configuration: configuration))
        XCTAssertTrue(engine.ingest(bpm: 105, zone: .zone0, at: start.addingTimeInterval(5), configuration: configuration))

        engine.snooze(for: 20, at: start.addingTimeInterval(6))
        guard case let .snoozed(remaining) = engine.semanticState(
            at: start.addingTimeInterval(10),
            configuration: configuration
        ) else {
            return XCTFail("Expected snoozed state")
        }
        XCTAssertEqual(remaining, 16, accuracy: 0.001)
        XCTAssertEqual(FocusDotSemanticState.snoozed(remaining: remaining).tone, .amber)
        XCTAssertFalse(engine.ingest(bpm: 106, zone: .zone0, at: start.addingTimeInterval(20), configuration: configuration))

        XCTAssertTrue(engine.ingest(bpm: 106, zone: .zone0, at: start.addingTimeInterval(27), configuration: configuration))
        guard case .elevated = engine.semanticState(
            at: start.addingTimeInterval(27),
            configuration: configuration
        ) else {
            return XCTFail("Expected elevation to remain active after snooze")
        }
    }

    func testResetAndStaleClearElevationState() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.bpmThreshold = 100
        configuration.dwellSeconds = 0

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(engine.ingest(bpm: 101, zone: .zone0, at: start, configuration: configuration))
        engine.resetElevation()
        XCTAssertEqual(engine.semanticState(at: start, configuration: configuration), .normal)

        XCTAssertFalse(engine.ingest(bpm: 101, zone: .zone0, at: start.addingTimeInterval(1), configuration: configuration))
        engine.markDataStale()
        XCTAssertEqual(engine.semanticState(at: start.addingTimeInterval(1), configuration: configuration), .normal)
        XCTAssertEqual(FocusDotSemanticState.stale.tone, .unavailable)
        XCTAssertEqual(FocusDotSemanticState.disconnected.tone, .unavailable)
    }

    func testExplicitNoContactResetsDwellAndCannotAlert() {
        var engine = ThresholdEngine()
        var configuration = AlertConfiguration()
        configuration.isEnabled = true
        configuration.bpmThreshold = 100
        configuration.dwellSeconds = 5

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(engine.ingest(
            bpm: 105,
            zone: .zone0,
            sensorContactDetected: true,
            at: start,
            configuration: configuration
        ))
        XCTAssertFalse(engine.ingest(
            bpm: 110,
            zone: .zone0,
            sensorContactDetected: false,
            at: start.addingTimeInterval(5),
            configuration: configuration
        ))
        XCTAssertEqual(engine.semanticState(
            at: start.addingTimeInterval(5),
            configuration: configuration
        ), .normal)

        XCTAssertFalse(engine.ingest(
            bpm: 108,
            zone: .zone0,
            sensorContactDetected: true,
            at: start.addingTimeInterval(10),
            configuration: configuration
        ))
        XCTAssertTrue(engine.ingest(
            bpm: 108,
            zone: .zone0,
            sensorContactDetected: true,
            at: start.addingTimeInterval(15),
            configuration: configuration
        ))
    }
}
