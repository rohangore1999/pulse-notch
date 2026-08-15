import Foundation
import XCTest
@testable import PulseNotch

final class HeartRateMeasurementParserTests: XCTestCase {
    func testParsesEightBitHeartRate() throws {
        let measurement = try HeartRateMeasurementParser.parse(Data([0x00, 72]))
        XCTAssertEqual(measurement.bpm, 72)
        XCTAssertNil(measurement.sensorContactDetected)
        XCTAssertNil(measurement.energyExpended)
        XCTAssertTrue(measurement.rrIntervals.isEmpty)
    }

    func testParsesSixteenBitHeartRate() throws {
        let measurement = try HeartRateMeasurementParser.parse(Data([0x01, 0x2C, 0x01]))
        XCTAssertEqual(measurement.bpm, 300)
    }

    func testParsesSensorContactFlags() throws {
        let notDetected = try HeartRateMeasurementParser.parse(Data([0x04, 75]))
        let detected = try HeartRateMeasurementParser.parse(Data([0x06, 75]))
        XCTAssertEqual(notDetected.sensorContactDetected, false)
        XCTAssertEqual(detected.sensorContactDetected, true)
    }

    func testParsesEnergyAndRRIntervals() throws {
        let measurement = try HeartRateMeasurementParser.parse(
            Data([0x18, 60, 0x34, 0x12, 0x00, 0x04, 0x00, 0x02])
        )
        XCTAssertEqual(measurement.energyExpended, 0x1234)
        XCTAssertEqual(measurement.rrIntervals, [1.0, 0.5])
    }

    func testRejectsMalformedPackets() {
        XCTAssertThrowsError(try HeartRateMeasurementParser.parse(Data()))
        XCTAssertThrowsError(try HeartRateMeasurementParser.parse(Data([0x00])))
        XCTAssertThrowsError(try HeartRateMeasurementParser.parse(Data([0x01, 0x2C])))
        XCTAssertThrowsError(try HeartRateMeasurementParser.parse(Data([0x08, 70, 0x01])))
        XCTAssertThrowsError(try HeartRateMeasurementParser.parse(Data([0x10, 70])))
        XCTAssertThrowsError(try HeartRateMeasurementParser.parse(Data([0x10, 70, 0x01])))
        XCTAssertThrowsError(try HeartRateMeasurementParser.parse(Data([0x00, 70, 0x01])))
    }
}
