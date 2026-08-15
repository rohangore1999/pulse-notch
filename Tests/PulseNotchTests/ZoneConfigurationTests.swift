import XCTest
@testable import PulseNotch

final class ZoneConfigurationTests: XCTestCase {
    func testCalculatesHRRBoundaries() {
        let zones = ZoneConfiguration.fromHRR(restingHeartRate: 60, maximumHeartRate: 190)
        XCTAssertEqual(zones.lowerBounds, [112, 138, 151, 164, 177])
        XCTAssertTrue(zones.isValid)
    }

    func testClassifiesBoundaryIntoHigherZone() {
        let zones = ZoneConfiguration.fromHRR(restingHeartRate: 60, maximumHeartRate: 190)
        XCTAssertEqual(zones.zone(for: 111), .zone0)
        XCTAssertEqual(zones.zone(for: 112), .zone1)
        XCTAssertEqual(zones.zone(for: 138), .zone2)
        XCTAssertEqual(zones.zone(for: 151), .zone3)
        XCTAssertEqual(zones.zone(for: 164), .zone4)
        XCTAssertEqual(zones.zone(for: 177), .zone5)
        XCTAssertEqual(zones.zone(for: 205), .zone5)
    }

    func testRejectsNonIncreasingBoundaries() {
        var zones = ZoneConfiguration.example
        zones.zone3Lower = zones.zone2Lower
        XCTAssertFalse(zones.isValid)
    }
}
