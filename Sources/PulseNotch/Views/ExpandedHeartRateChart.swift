import SwiftUI

struct ExpandedHeartRateChart: View {
    let samples: [HeartRateSample]
    let thresholdBPM: Int
    let accent: Color
    let isStale: Bool
    let plotHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let windowStart = timeline.date.addingTimeInterval(
                -HeartRateChartPolicy.expandedWindow
            )
            let rawVisible = HeartRateChartPolicy.windowedSamples(
                samples,
                endingAt: timeline.date,
                duration: HeartRateChartPolicy.expandedWindow
            )
            let averageRuns = HeartRateChartPolicy.minuteAverageRuns(
                fromSorted: rawVisible,
                calendar: .current,
                lowerBound: windowStart
            )
            let bounds = HeartRateChartPolicy.bounds(
                for: averageRuns.flatMap { $0 },
                thresholdBPM: thresholdBPM
            )

            VStack(spacing: 2) {
                plot(
                    averageRuns: averageRuns,
                    bounds: bounds,
                    endingAt: timeline.date
                )
                .frame(height: plotHeight)

                timeAxis(endingAt: timeline.date)
            }
        }
    }

    private func plot(
        averageRuns: [[HeartRateSample]],
        bounds: HeartRateChartBounds,
        endingAt end: Date
    ) -> some View {
        GeometryReader { proxy in
            let geometry = PlotGeometry(
                size: proxy.size,
                bounds: bounds,
                endingAt: end
            )
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawChart(
                        context: &context,
                        size: size,
                        averageRuns: averageRuns,
                        geometry: geometry
                    )
                }

                ChartHoverOverlay(
                    runs: averageRuns,
                    geometry: geometry,
                    accent: accent
                )
            }
        }
    }

    private func drawChart(
        context: inout GraphicsContext,
        size: CGSize,
        averageRuns: [[HeartRateSample]],
        geometry: PlotGeometry
    ) {
        guard let latestAverage = averageRuns.last?.last else {
            drawPlaceholder(context: &context, size: size, geometry: geometry)
            return
        }

        drawThreshold(context: &context, geometry: geometry)

        var areaPath = Path()
        var neutralPath = Path()
        var accentPath = Path()
        var isolatedPoints: [CGPoint] = []

        for run in averageRuns {
            let duration = max(
                1,
                (run.last?.timestamp ?? geometry.endingAt)
                    .timeIntervalSince(run.first?.timestamp ?? geometry.endingAt)
            )
            let fraction = min(1, duration / HeartRateChartPolicy.expandedWindow)
            let maximumPoints = max(4, Int(Double(size.width) * 2 * fraction))
            let plotted = HeartRateChartPolicy.downsampledForPlot(
                run,
                maximumPoints: maximumPoints
            )

            guard let first = plotted.first, let last = plotted.last else { continue }
            guard plotted.count > 1 else { continue }

            let firstPoint = geometry.point(for: first)
            let lastPoint = geometry.point(for: last)
            areaPath.move(to: CGPoint(x: firstPoint.x, y: geometry.plotBottom))
            plotted.forEach { areaPath.addLine(to: geometry.point(for: $0)) }
            areaPath.addLine(to: CGPoint(x: lastPoint.x, y: geometry.plotBottom))
            areaPath.closeSubpath()
        }

        for run in averageRuns {
            let duration = max(
                1,
                (run.last?.timestamp ?? geometry.endingAt)
                    .timeIntervalSince(run.first?.timestamp ?? geometry.endingAt)
            )
            let fraction = min(1, duration / HeartRateChartPolicy.expandedWindow)
            let maximumPoints = max(4, Int(Double(size.width) * 2 * fraction))
            let plotted = HeartRateChartPolicy.downsampledForPlot(
                run,
                maximumPoints: maximumPoints
            )

            guard let first = plotted.first else { continue }
            if plotted.count == 1 {
                isolatedPoints.append(geometry.point(for: first))
                continue
            }

            for index in 1..<plotted.count {
                let prior = plotted[index - 1]
                let sample = plotted[index]
                let isAboveThreshold = prior.bpm >= thresholdBPM || sample.bpm >= thresholdBPM
                if isAboveThreshold {
                    accentPath.move(to: geometry.point(for: prior))
                    accentPath.addLine(to: geometry.point(for: sample))
                } else {
                    neutralPath.move(to: geometry.point(for: prior))
                    neutralPath.addLine(to: geometry.point(for: sample))
                }
            }
        }

        context.fill(
            areaPath,
            with: .linearGradient(
                Gradient(colors: [accent.opacity(0.24), accent.opacity(0.01)]),
                startPoint: CGPoint(x: 0, y: geometry.plotTop),
                endPoint: CGPoint(x: 0, y: geometry.plotBottom)
            )
        )
        context.stroke(
            neutralPath,
            with: .color(Color.white.opacity(0.40)),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            accentPath,
            with: .color(accent),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )

        for point in isolatedPoints {
            let dot = Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
            context.fill(dot, with: .color(accent))
        }

        let point = geometry.point(for: latestAverage)
        let isFresh = !isStale
        let halo = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        let dot = Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
        context.fill(halo, with: .color(accent.opacity(isFresh ? 0.16 : 0)))
        context.fill(dot, with: .color(isFresh ? accent : FocusDotTheme.unavailable))
    }

    private func drawThreshold(
        context: inout GraphicsContext,
        geometry: PlotGeometry
    ) {
        let y = geometry.y(for: thresholdBPM)
        var path = Path()
        path.move(to: CGPoint(x: geometry.plotStartX, y: y))
        path.addLine(to: CGPoint(x: geometry.plotEndX, y: y))
        context.stroke(
            path,
            with: .color(Color.white.opacity(0.28)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )
    }

    private func drawPlaceholder(
        context: inout GraphicsContext,
        size: CGSize,
        geometry: PlotGeometry
    ) {
        drawThreshold(context: &context, geometry: geometry)
        var line = Path()
        let y = size.height / 2
        line.move(to: CGPoint(x: geometry.plotStartX, y: y))
        line.addCurve(
            to: CGPoint(x: geometry.plotEndX, y: y),
            control1: CGPoint(x: size.width * 0.32, y: y - 2),
            control2: CGPoint(x: size.width * 0.68, y: y + 2)
        )
        context.stroke(
            line,
            with: .color(FocusDotTheme.unavailable.opacity(0.54)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
        )
    }

    private func timeAxis(endingAt end: Date) -> some View {
        HStack {
            Text(end.addingTimeInterval(-HeartRateChartPolicy.expandedWindow).formatted(date: .omitted, time: .shortened))
            Spacer()
            Text(end.addingTimeInterval(-HeartRateChartPolicy.expandedWindow / 2).formatted(date: .omitted, time: .shortened))
            Spacer()
            Text("Now")
        }
        .font(.system(size: 10, weight: .regular))
        .foregroundStyle(FocusDotTheme.textSecondary)
    }

}

private struct ChartHoverOverlay: View {
    let runs: [[HeartRateSample]]
    let geometry: PlotGeometry
    let accent: Color

    @State private var hoverLocation: CGPoint?

    var body: some View {
        let selection = hoverSelection

        ZStack(alignment: .topLeading) {
            Color.clear

            if let selection {
                hoverDecoration(selection)
            }
        }
        .contentShape(Rectangle())
        .crosshairCursor()
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                hoverLocation = location
            case .ended:
                hoverLocation = nil
            }
        }
        .onDisappear {
            hoverLocation = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live one-hour heart-rate minute averages")
        .accessibilityValue(accessibilityValue(selection: selection))
    }

    private var hoverSelection: HoverSelection? {
        guard let hoverLocation,
              let target = HeartRateChartPolicy.timestamp(
                atX: Double(hoverLocation.x),
                plotStartX: Double(geometry.plotStartX),
                plotWidth: Double(geometry.plotWidth),
                endingAt: geometry.endingAt,
                duration: HeartRateChartPolicy.expandedWindow
              ) else { return nil }

        let secondsPerPoint = HeartRateChartPolicy.expandedWindow
            / max(1, Double(geometry.plotWidth))
        let interiorSnapDistance = max(
            secondsPerPoint,
            HeartRateChartPolicy.minuteContinuityGap / 2
        )
        let endpointSnapDistance = min(15, interiorSnapDistance)
        let candidates = runs.compactMap { run -> HeartRateSample? in
            guard let first = run.first, let last = run.last else { return nil }
            let isInsideRun = target >= first.timestamp && target <= last.timestamp
            return HeartRateChartPolicy.hoverSample(
                to: target,
                in: run,
                maximumDistance: isInsideRun
                    ? interiorSnapDistance
                    : endpointSnapDistance,
                maximumGap: HeartRateChartPolicy.minuteContinuityGap,
                gapEndpointTolerance: endpointSnapDistance
            )
        }
        guard let sample = candidates.min(by: { lhs, rhs in
            let lhsTimeDistance = abs(lhs.timestamp.timeIntervalSince(target))
            let rhsTimeDistance = abs(rhs.timestamp.timeIntervalSince(target))
            if lhsTimeDistance != rhsTimeDistance {
                return lhsTimeDistance < rhsTimeDistance
            }

            let lhsVerticalDistance = abs(geometry.point(for: lhs).y - hoverLocation.y)
            let rhsVerticalDistance = abs(geometry.point(for: rhs).y - hoverLocation.y)
            if lhsVerticalDistance != rhsVerticalDistance {
                return lhsVerticalDistance < rhsVerticalDistance
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }) else { return nil }
        return HoverSelection(sample: sample, point: geometry.point(for: sample))
    }

    private func hoverDecoration(_ selection: HoverSelection) -> some View {
        let tooltipWidth: CGFloat = 132
        let tooltipHeight: CGFloat = 24
        let tooltipX = min(
            geometry.size.width - tooltipWidth / 2 - 4,
            max(tooltipWidth / 2 + 4, selection.point.x)
        )
        let tooltipY = selection.point.y > tooltipHeight + 12
            ? selection.point.y - tooltipHeight / 2 - 7
            : min(geometry.size.height - tooltipHeight / 2 - 2, selection.point.y + tooltipHeight / 2 + 7)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: geometry.plotHeight)
                .position(x: selection.point.x, y: geometry.plotTop + geometry.plotHeight / 2)

            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                }
                .position(selection.point)

            HStack(spacing: 6) {
                Text(selection.sample.timestamp.formatted(date: .omitted, time: .shortened))
                Circle()
                    .fill(FocusDotTheme.textTertiary)
                    .frame(width: 2, height: 2)
                Text("\(selection.sample.bpm) BPM avg")
                    .monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(FocusDotTheme.textPrimary)
            .frame(width: tooltipWidth, height: tooltipHeight)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(FocusDotTheme.panel.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
            )
            .position(x: tooltipX, y: tooltipY)
        }
        .allowsHitTesting(false)
    }

    private func accessibilityValue(selection: HoverSelection?) -> String {
        if let selection {
            return "\(selection.sample.bpm) beats per minute average at \(selection.sample.timestamp.formatted(date: .omitted, time: .shortened))"
        }
        if let latest = runs.last?.last {
            return "Latest minute average \(latest.bpm) beats per minute at \(latest.timestamp.formatted(date: .omitted, time: .shortened))"
        }
        return "No minute averages in the last hour"
    }
}

private struct HoverSelection {
    let sample: HeartRateSample
    let point: CGPoint
}

private struct PlotGeometry {
    let size: CGSize
    let bounds: HeartRateChartBounds
    let endingAt: Date

    let leadingInset: CGFloat = 5
    let trailingInset: CGFloat = 24
    let verticalInset: CGFloat = 5

    var plotStartX: CGFloat { min(size.width / 2, leadingInset) }
    var plotEndX: CGFloat { max(plotStartX, size.width - trailingInset) }
    var plotWidth: CGFloat { max(1, plotEndX - plotStartX) }
    var plotTop: CGFloat { verticalInset }
    var plotBottom: CGFloat { max(plotTop, size.height - verticalInset) }
    var plotHeight: CGFloat { max(1, plotBottom - plotTop) }

    func point(for sample: HeartRateSample) -> CGPoint {
        let start = endingAt.addingTimeInterval(-HeartRateChartPolicy.expandedWindow)
        let elapsed = sample.timestamp.timeIntervalSince(start)
        let progress = min(1, max(0, elapsed / HeartRateChartPolicy.expandedWindow))
        return CGPoint(
            x: plotStartX + CGFloat(progress) * plotWidth,
            y: y(for: sample.bpm)
        )
    }

    func y(for bpm: Int) -> CGFloat {
        let span = max(1, bounds.maximumBPM - bounds.minimumBPM)
        let normalized = Double(bpm - bounds.minimumBPM) / Double(span)
        return plotBottom - CGFloat(min(1, max(0, normalized))) * plotHeight
    }
}
