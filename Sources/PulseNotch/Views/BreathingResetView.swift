import SwiftUI

struct BreathingResetView: View {
    let secondsRemaining: Int
    let accent: Color
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var elapsed: Int { max(0, 60 - secondsRemaining) }
    private var phaseSecond: Int { elapsed % 10 }
    private var isInhaling: Bool { phaseSecond < 4 }
    private var orbScale: CGFloat {
        if isInhaling {
            return 0.76 + 0.24 * CGFloat(phaseSecond + 1) / 4
        }
        return 1 - 0.24 * CGFloat(phaseSecond - 3) / 6
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("60-second reset")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FocusDotTheme.textSecondary)
                Spacer()
                Text(isInhaling ? "Inhale" : "Exhale")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    .frame(width: 92, height: 92)

                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 82, height: 82)
                    .scaleEffect(reduceMotion ? 1 : orbScale)

                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 58, height: 58)

                Image(systemName: "lungs.fill")
                    .font(.system(size: 24, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
            .frame(height: 94)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1), value: secondsRemaining)

            Text(timeText)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(FocusDotTheme.textPrimary)

            Text("Inhale 4 · Exhale 6")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FocusDotTheme.liveHighlight)

            Button("Stop", action: stop)
                .buttonStyle(FocusDotActionButtonStyle(.secondary))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("60-second reset")
    }

    private var timeText: String {
        let seconds = max(0, secondsRemaining)
        return String(format: "0:%02d", seconds)
    }
}
