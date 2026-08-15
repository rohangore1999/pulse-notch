import SwiftUI

struct SparklineView: View {
    enum Style {
        case compact
        case expanded
    }

    let samples: [HeartRateSample]
    let minimumBPM: Int
    let maximumBPM: Int
    let isStale: Bool
    var thresholdBPM: Int? = nil
    var accent: Color = FocusDotTheme.live
    var style: Style = .compact
    var window: TimeInterval = 60

    var body: some View {
        Canvas { context, size in
            let visible = visibleSamples
            guard !visible.isEmpty else {
                drawPlaceholder(context: &context, size: size)
                return
            }

            let newest = visible.last?.timestamp ?? Date()
            let oldest = newest.addingTimeInterval(-window)
            let bpmSpan = max(1, maximumBPM - minimumBPM)

            func point(for sample: HeartRateSample) -> CGPoint {
                let seconds = sample.timestamp.timeIntervalSince(oldest)
                // Keep the newest marker centered inside the canvas instead of
                // placing its center on the trailing edge and clipping half of it.
                let leadingInset = min(size.width / 2, 5)
                let desiredTrailingInset: CGFloat = style == .compact ? 5 : 24
                let trailingInset = min(max(0, size.width - leadingInset), desiredTrailingInset)
                let plotWidth = max(0, size.width - leadingInset - trailingInset)
                let progress = min(1, max(0, seconds / window))
                let x = leadingInset + progress * plotWidth
                let normalized = Double(sample.bpm - minimumBPM) / Double(bpmSpan)
                let verticalInset: CGFloat = style == .compact ? 4 : 5
                let plotHeight = max(1, size.height - verticalInset * 2)
                let y = size.height - verticalInset - min(1, max(0, normalized)) * plotHeight
                return CGPoint(x: x, y: y)
            }

            context.opacity = isStale ? 0.34 : 1

            if style == .expanded, let thresholdBPM {
                let normalized = Double(thresholdBPM - minimumBPM) / Double(bpmSpan)
                let plotHeight = max(1, size.height - 10)
                let y = size.height - 5 - min(1, max(0, normalized)) * plotHeight
                var threshold = Path()
                threshold.move(to: CGPoint(x: 0, y: y))
                threshold.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    threshold,
                    with: .color(Color.white.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }

            if visible.count == 1, let sample = visible.first {
                let center = point(for: sample)
                let dot = Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(accent))
                return
            }

            if style == .expanded {
                var area = Path()
                if let first = visible.first, let last = visible.last {
                    area.move(to: CGPoint(x: point(for: first).x, y: size.height))
                    visible.forEach { area.addLine(to: point(for: $0)) }
                    area.addLine(to: CGPoint(x: point(for: last).x, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [accent.opacity(0.24), accent.opacity(0.01)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))
                }
            }

            for index in 1..<visible.count {
                let prior = visible[index - 1]
                let sample = visible[index]
                var segment = Path()
                segment.move(to: point(for: prior))
                segment.addLine(to: point(for: sample))

                let isAboveThreshold = thresholdBPM.map { sample.bpm >= $0 || prior.bpm >= $0 } ?? false
                let segmentColor: Color
                if style == .expanded, thresholdBPM != nil, !isAboveThreshold {
                    segmentColor = Color.white.opacity(0.40)
                } else {
                    segmentColor = accent
                }

                context.stroke(
                    segment,
                    with: .color(segmentColor),
                    style: StrokeStyle(
                        lineWidth: style == .compact ? 1.45 : 1.8,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if let sample = visible.last {
                let center = point(for: sample)
                let halo = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                let dot = Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
                context.fill(halo, with: .color(accent.opacity(isStale ? 0 : 0.16)))
                context.fill(dot, with: .color(isStale ? FocusDotTheme.unavailable : accent))
            }
        }
        .accessibilityLabel("Live heart-rate history")
        .accessibilityValue(samples.last.map { "\($0.bpm) beats per minute" } ?? "No readings")
    }

    private var visibleSamples: [HeartRateSample] {
        guard let newest = samples.max(by: { $0.timestamp < $1.timestamp })?.timestamp else { return [] }
        let cutoff = newest.addingTimeInterval(-window)
        return samples
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func drawPlaceholder(context: inout GraphicsContext, size: CGSize) {
        var line = Path()
        let y = size.height / 2
        line.move(to: CGPoint(x: 0, y: y))
        line.addCurve(
            to: CGPoint(x: size.width, y: y),
            control1: CGPoint(x: size.width * 0.32, y: y - 2),
            control2: CGPoint(x: size.width * 0.68, y: y + 2)
        )
        context.stroke(
            line,
            with: .color(FocusDotTheme.unavailable.opacity(0.54)),
            style: StrokeStyle(lineWidth: 1, dash: style == .compact ? [] : [3, 4])
        )
    }
}
