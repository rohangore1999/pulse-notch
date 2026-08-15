import Foundation

enum HeartRateMeasurementParser {
    enum ParseError: Error, Equatable {
        case missingFlags
        case truncatedHeartRate
        case truncatedEnergyExpended
        case truncatedRRInterval
        case invalidHeartRate
    }

    static func parse(_ data: Data) throws -> HeartRateMeasurement {
        guard let flags = data.first else { throw ParseError.missingFlags }
        var offset = 1

        let bpm: Int
        if flags & 0x01 == 0 {
            guard data.count > offset else { throw ParseError.truncatedHeartRate }
            bpm = Int(data[offset])
            offset += 1
        } else {
            guard data.count >= offset + 2 else { throw ParseError.truncatedHeartRate }
            bpm = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            offset += 2
        }

        let contactSupported = flags & 0x04 != 0
        let contactDetected: Bool? = contactSupported ? flags & 0x02 != 0 : nil

        var energyExpended: UInt16?
        if flags & 0x08 != 0 {
            guard data.count >= offset + 2 else { throw ParseError.truncatedEnergyExpended }
            energyExpended = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            offset += 2
        }

        var rrIntervals: [Double] = []
        if flags & 0x10 != 0 {
            guard data.count > offset else { throw ParseError.truncatedRRInterval }
            guard (data.count - offset).isMultiple(of: 2) else {
                throw ParseError.truncatedRRInterval
            }
            while offset + 1 < data.count {
                let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                rrIntervals.append(Double(raw) / 1024.0)
                offset += 2
            }
        } else if offset != data.count {
            throw ParseError.truncatedRRInterval
        }

        return HeartRateMeasurement(
            bpm: bpm,
            sensorContactDetected: contactDetected,
            energyExpended: energyExpended,
            rrIntervals: rrIntervals
        )
    }
}
