import Foundation

struct HeartRateChartBounds: Equatable {
    let minimumBPM: Int
    let maximumBPM: Int
}

enum HeartRateChartPolicy {
    static let compactWindow: TimeInterval = 60
    static let compactRetention: TimeInterval = 180
    static let expandedWindow: TimeInterval = 60 * 60
    static let expandedMaximumSampleCount = 36_000
    static let continuityGap: TimeInterval = 5
    static let minuteContinuityGap: TimeInterval = 90

    static func minuteAverages(
        _ samples: [HeartRateSample],
        calendar: Calendar = .current
    ) -> [HeartRateSample] {
        let ordered = samples.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
        return minuteAverages(fromSorted: ordered, calendar: calendar)
    }

    static func minuteAverages(
        fromSorted samples: [HeartRateSample],
        calendar: Calendar = .current,
        lowerBound: Date? = nil
    ) -> [HeartRateSample] {
        guard !samples.isEmpty else { return [] }

        var averages: [HeartRateSample] = []
        averages.reserveCapacity(min(samples.count, 61))

        var bucketStart: Date?
        var bucketID: UUID?
        var latestSample: HeartRateSample?
        var bpmTotal = 0
        var sampleCount = 0

        func appendCurrentBucket() {
            guard let bucketStart,
                  let bucketID,
                  let latestSample,
                  sampleCount > 0 else { return }
            let average = Int((Double(bpmTotal) / Double(sampleCount)).rounded())
            averages.append(
                HeartRateSample(
                    id: bucketID,
                    timestamp: lowerBound.map { max(bucketStart, $0) } ?? bucketStart,
                    bpm: average,
                    zone: latestSample.zone
                )
            )
        }

        for sample in samples {
            let minuteStart = calendar.dateInterval(of: .minute, for: sample.timestamp)?.start
                ?? Date(
                    timeIntervalSince1970:
                        floor(sample.timestamp.timeIntervalSince1970 / 60) * 60
                )

            if minuteStart != bucketStart {
                appendCurrentBucket()
                bucketStart = minuteStart
                bucketID = sample.id
                latestSample = sample
                bpmTotal = sample.bpm
                sampleCount = 1
            } else {
                latestSample = sample
                bpmTotal += sample.bpm
                sampleCount += 1
            }
        }

        appendCurrentBucket()
        return averages
    }

    static func minuteAverageRuns(
        fromSorted samples: [HeartRateSample],
        calendar: Calendar = .current,
        lowerBound: Date? = nil
    ) -> [[HeartRateSample]] {
        continuousRuns(samples, maximumGap: continuityGap).compactMap { rawRun in
            let averages = minuteAverages(
                fromSorted: rawRun,
                calendar: calendar,
                lowerBound: lowerBound
            )
            return averages.isEmpty ? nil : averages
        }
    }

    static func retainedSamples(
        _ samples: [HeartRateSample],
        appending sample: HeartRateSample,
        duration: TimeInterval,
        maximumCount: Int
    ) -> [HeartRateSample] {
        let cutoff = sample.timestamp.addingTimeInterval(-max(0, duration))
        var retained = samples
        retained.append(sample)
        if retained.count > 1,
           retained[retained.count - 2].timestamp > sample.timestamp {
            retained.sort { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }
        }

        var lower = 0
        var upper = retained.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if retained[middle].timestamp < cutoff {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower > 0 {
            retained.removeFirst(lower)
        }

        guard maximumCount > 0, retained.count > maximumCount else {
            return maximumCount > 0 ? retained : []
        }
        return Array(retained.suffix(maximumCount))
    }

    static func windowedSamples(
        _ samples: [HeartRateSample],
        endingAt end: Date,
        duration: TimeInterval
    ) -> [HeartRateSample] {
        let start = end.addingTimeInterval(-max(0, duration))
        return samples
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }
    }

    static func continuousRuns(
        _ sortedSamples: [HeartRateSample],
        maximumGap: TimeInterval = continuityGap
    ) -> [[HeartRateSample]] {
        guard let first = sortedSamples.first else { return [] }
        var runs: [[HeartRateSample]] = [[first]]

        for sample in sortedSamples.dropFirst() {
            guard let previous = runs[runs.count - 1].last else { continue }
            if sample.timestamp.timeIntervalSince(previous.timestamp) > maximumGap {
                runs.append([sample])
            } else {
                runs[runs.count - 1].append(sample)
            }
        }
        return runs
    }

    static func downsampledForPlot(
        _ sortedSamples: [HeartRateSample],
        maximumPoints: Int
    ) -> [HeartRateSample] {
        guard maximumPoints > 0 else { return [] }
        guard sortedSamples.count > maximumPoints else { return sortedSamples }
        guard maximumPoints >= 4,
              let first = sortedSamples.first,
              let last = sortedSamples.last else {
            if maximumPoints == 1 { return [sortedSamples[sortedSamples.count / 2]] }
            return [sortedSamples.first, sortedSamples.last].compactMap { $0 }
        }

        let interior = Array(sortedSamples.dropFirst().dropLast())
        let bucketCount = max(1, (maximumPoints - 2) / 2)
        var result: [HeartRateSample] = [first]
        result.reserveCapacity(maximumPoints)

        for bucket in 0..<bucketCount {
            let lower = Int(Double(bucket) * Double(interior.count) / Double(bucketCount))
            let upper = Int(Double(bucket + 1) * Double(interior.count) / Double(bucketCount))
            guard lower < upper else { continue }
            let slice = interior[lower..<upper]
            guard let minimum = slice.min(by: { $0.bpm < $1.bpm }),
                  let maximum = slice.max(by: { $0.bpm < $1.bpm }) else { continue }

            if minimum.id == maximum.id {
                result.append(minimum)
            } else if minimum.timestamp < maximum.timestamp {
                result.append(minimum)
                result.append(maximum)
            } else {
                result.append(maximum)
                result.append(minimum)
            }
        }

        if result.last?.id != last.id {
            result.append(last)
        }
        return result
    }

    static func nearestSample(
        to target: Date,
        in sortedSamples: [HeartRateSample],
        maximumDistance: TimeInterval
    ) -> HeartRateSample? {
        guard !sortedSamples.isEmpty, maximumDistance >= 0 else { return nil }

        var lower = 0
        var upper = sortedSamples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if sortedSamples[middle].timestamp < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        let candidates = [lower - 1, lower]
            .filter { sortedSamples.indices.contains($0) }
            .map { sortedSamples[$0] }
        guard let nearest = candidates.min(by: { lhs, rhs in
            let lhsDistance = abs(lhs.timestamp.timeIntervalSince(target))
            let rhsDistance = abs(rhs.timestamp.timeIntervalSince(target))
            if lhsDistance == rhsDistance {
                return lhs.timestamp < rhs.timestamp
            }
            return lhsDistance < rhsDistance
        }),
              abs(nearest.timestamp.timeIntervalSince(target)) <= maximumDistance else {
            return nil
        }
        return nearest
    }

    static func hoverSample(
        to target: Date,
        in sortedSamples: [HeartRateSample],
        maximumDistance: TimeInterval,
        maximumGap: TimeInterval = continuityGap,
        gapEndpointTolerance: TimeInterval = 1
    ) -> HeartRateSample? {
        guard let nearest = nearestSample(
            to: target,
            in: sortedSamples,
            maximumDistance: maximumDistance
        ) else { return nil }

        var lower = 0
        var upper = sortedSamples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if sortedSamples[middle].timestamp < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        if lower > 0, lower < sortedSamples.count {
            let previous = sortedSamples[lower - 1]
            let next = sortedSamples[lower]
            let gap = next.timestamp.timeIntervalSince(previous.timestamp)
            let targetIsInsideGap = target > previous.timestamp && target < next.timestamp
            if gap > maximumGap,
               targetIsInsideGap,
               abs(nearest.timestamp.timeIntervalSince(target)) > gapEndpointTolerance {
                return nil
            }
        }

        return nearest
    }

    static func timestamp(
        atX x: Double,
        plotStartX: Double,
        plotWidth: Double,
        endingAt end: Date,
        duration: TimeInterval
    ) -> Date? {
        guard plotWidth > 0, duration >= 0 else { return nil }
        let progress = min(1, max(0, (x - plotStartX) / plotWidth))
        return end.addingTimeInterval(-duration * (1 - progress))
    }

    static func bounds(
        for samples: [HeartRateSample],
        thresholdBPM: Int
    ) -> HeartRateChartBounds {
        let sampleMinimum = samples.reduce(thresholdBPM - 35) { min($0, $1.bpm - 8) }
        let sampleMaximum = samples.reduce(thresholdBPM + 12) { max($0, $1.bpm + 8) }
        let roundedMinimum = Int(floor(Double(sampleMinimum) / 5) * 5)
        let roundedMaximum = Int(ceil(Double(sampleMaximum) / 5) * 5)
        let minimum = max(20, roundedMinimum)
        let maximum = max(minimum + 5, roundedMaximum)
        return HeartRateChartBounds(minimumBPM: minimum, maximumBPM: maximum)
    }
}
