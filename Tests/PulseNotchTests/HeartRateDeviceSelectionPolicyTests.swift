import Foundation
import XCTest
@testable import PulseNotch

final class HeartRateDeviceSelectionPolicyTests: XCTestCase {
    private let approvedID = UUID(
        uuidString: "00000000-0000-0000-0000-00000000ABCD"
    )!
    private let otherID = UUID(
        uuidString: "00000000-0000-0000-0000-00000000BCDE"
    )!

    func testExplicitPickerNeverAutomaticallySelectsCandidate() {
        XCTAssertFalse(HeartRateDeviceSelectionPolicy.shouldAutomaticallyReconnect(
            candidateID: approvedID,
            approvedDeviceID: approvedID,
            isExplicitPickerScan: true
        ))
        XCTAssertTrue(HeartRateDeviceSelectionPolicy.shouldAutomaticallyReconnect(
            candidateID: approvedID,
            approvedDeviceID: approvedID,
            isExplicitPickerScan: false
        ))
        XCTAssertFalse(HeartRateDeviceSelectionPolicy.shouldAutomaticallyReconnect(
            candidateID: otherID,
            approvedDeviceID: approvedID,
            isExplicitPickerScan: false
        ))
    }

    func testApprovalRequiresCompleteStoredRecord() {
        XCTAssertEqual(
            HeartRateDeviceSelectionPolicy.restoredApprovedDevice(
                identifierString: approvedID.uuidString,
                name: "  Alex’s WHOOP  "
            ),
            ApprovedHeartRateDeviceRecord(identifier: approvedID, name: "Alex’s WHOOP")
        )
        XCTAssertNil(HeartRateDeviceSelectionPolicy.restoredApprovedDevice(
            identifierString: approvedID.uuidString,
            name: " "
        ))
        XCTAssertNil(HeartRateDeviceSelectionPolicy.restoredApprovedDevice(
            identifierString: "invalid",
            name: "Alex’s WHOOP"
        ))
    }

    func testOnlyValidLiveBPMCanApproveDevice() {
        XCTAssertTrue(HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 20))
        XCTAssertTrue(HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 260))
        XCTAssertFalse(HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 19))
        XCTAssertFalse(HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: 261))
    }

    func testRetryIsLimitedToApprovedDevice() {
        XCTAssertTrue(HeartRateDeviceSelectionPolicy.shouldRetryApprovedDevice(
            failedDeviceID: approvedID,
            approvedDeviceID: approvedID,
            userWantsMonitoring: true,
            bluetoothIsPoweredOn: true
        ))
        XCTAssertFalse(HeartRateDeviceSelectionPolicy.shouldRetryApprovedDevice(
            failedDeviceID: otherID,
            approvedDeviceID: approvedID,
            userWantsMonitoring: true,
            bluetoothIsPoweredOn: true
        ))
    }

    func testStaleCancellationCannotEndNewAttempt() {
        XCTAssertFalse(HeartRateDeviceSelectionPolicy.shouldProcessConnectionEnd(
            isCurrentPeripheral: true,
            wasCancellation: true,
            callbackDeviceID: approvedID,
            pendingTerminationDeviceID: nil
        ))
        XCTAssertTrue(HeartRateDeviceSelectionPolicy.shouldProcessConnectionEnd(
            isCurrentPeripheral: true,
            wasCancellation: true,
            callbackDeviceID: approvedID,
            pendingTerminationDeviceID: approvedID
        ))
    }
}
