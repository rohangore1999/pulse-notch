import Foundation

enum HeartRateZone: Int, CaseIterable, Codable, Identifiable, Comparable {
    case zone0 = 0
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    var id: Int { rawValue }
    var shortName: String { "Z\(rawValue)" }

    var label: String {
        switch self {
        case .zone0: "Resting"
        case .zone1: "Very light"
        case .zone2: "Light"
        case .zone3: "Moderate"
        case .zone4: "Hard"
        case .zone5: "Max effort"
        }
    }

    static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ZoneConfiguration: Codable, Equatable {
    var zone1Lower: Int
    var zone2Lower: Int
    var zone3Lower: Int
    var zone4Lower: Int
    var zone5Lower: Int
    var restingHeartRate: Int
    var maximumHeartRate: Int
    var source: CalibrationSource
    var verifiedAt: Date?

    enum CalibrationSource: String, Codable, CaseIterable, Identifiable {
        case whoopCopied
        case hrrCalculated
        case example

        var id: String { rawValue }

        var label: String {
            switch self {
            case .whoopCopied: "Copied from wearable settings"
            case .hrrCalculated: "Calculated from HRR"
            case .example: "Example values"
            }
        }
    }

    static let example = ZoneConfiguration.fromHRR(
        restingHeartRate: 60,
        maximumHeartRate: 190,
        source: .example
    )

    var isValid: Bool {
        let bounds = [zone1Lower, zone2Lower, zone3Lower, zone4Lower, zone5Lower]
        return zip(bounds, bounds.dropFirst()).allSatisfy { pair in
            pair.0 < pair.1
        }
            && restingHeartRate > 0
            && maximumHeartRate > restingHeartRate
    }

    var lowerBounds: [Int] {
        [zone1Lower, zone2Lower, zone3Lower, zone4Lower, zone5Lower]
    }

    func zone(for bpm: Int) -> HeartRateZone {
        if bpm >= zone5Lower { return .zone5 }
        if bpm >= zone4Lower { return .zone4 }
        if bpm >= zone3Lower { return .zone3 }
        if bpm >= zone2Lower { return .zone2 }
        if bpm >= zone1Lower { return .zone1 }
        return .zone0
    }

    static func fromHRR(
        restingHeartRate: Int,
        maximumHeartRate: Int,
        source: CalibrationSource = .hrrCalculated
    ) -> ZoneConfiguration {
        let reserve = max(1, maximumHeartRate - restingHeartRate)
        func lowerBound(_ intensity: Double) -> Int {
            Int(ceil(Double(restingHeartRate) + Double(reserve) * intensity))
        }

        return ZoneConfiguration(
            zone1Lower: lowerBound(0.40),
            zone2Lower: lowerBound(0.60),
            zone3Lower: lowerBound(0.70),
            zone4Lower: lowerBound(0.80),
            zone5Lower: lowerBound(0.90),
            restingHeartRate: restingHeartRate,
            maximumHeartRate: maximumHeartRate,
            source: source,
            verifiedAt: source == .whoopCopied ? Date() : nil
        )
    }
}

struct HeartRateSample: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let bpm: Int
    let zone: HeartRateZone

    init(id: UUID = UUID(), timestamp: Date, bpm: Int, zone: HeartRateZone) {
        self.id = id
        self.timestamp = timestamp
        self.bpm = bpm
        self.zone = zone
    }
}

struct HeartRateMeasurement: Equatable {
    let bpm: Int
    let sensorContactDetected: Bool?
    let energyExpended: UInt16?
    let rrIntervals: [Double]
}
