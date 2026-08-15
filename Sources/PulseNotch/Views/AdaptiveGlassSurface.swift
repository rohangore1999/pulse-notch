import SwiftUI

/// A reusable glass surface that progressively adopts macOS 26 Liquid Glass.
///
/// Place this view in a `background` or `overlay` and let its parent provide the
/// desired frame. Accessibility appearance settings always take precedence over
/// the system-version-specific treatment.
struct AdaptiveGlassSurface: View {
    let cornerRadius: CGFloat
    let tint: Color
    let tintOpacity: Double
    let isInteractive: Bool
    let highlighted: Bool
    let reflectionIntensity: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        cornerRadius: CGFloat,
        tint: Color,
        tintOpacity: Double = 0.22,
        isInteractive: Bool = false,
        highlighted: Bool = false,
        reflectionIntensity: Double = 1
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.isInteractive = isInteractive
        self.highlighted = highlighted
        self.reflectionIntensity = min(1, max(0, reflectionIntensity))
    }

    @ViewBuilder
    var body: some View {
        if reduceTransparency || contrast == .increased {
            accessibleSurface
        } else if #available(macOS 26.0, *) {
            liquidGlassSurface
        } else {
            materialSurface
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var effectiveTintOpacity: Double {
        min(1, max(0, tintOpacity + (highlighted ? 0.025 : 0)))
    }

    private func reflected(_ opacity: Double) -> Double {
        opacity * reflectionIntensity
    }

    /// The system material fallback used by the macOS 13–15 deployment range.
    private var materialSurface: some View {
        ZStack {
            shape.fill(.regularMaterial)
            shape.fill(Color.black.opacity(highlighted ? 0.42 : 0.54))
            shape.fill(tint.opacity(effectiveTintOpacity))
        }
        .clipShape(shape)
        .overlay(specularRim)
        .overlay(highlightRim)
    }

    /// A non-translucent, strongly delineated alternative for accessibility.
    private var accessibleSurface: some View {
        ZStack {
            shape.fill(Color(red: 0.025, green: 0.029, blue: 0.036))
            shape.fill(tint.opacity(min(0.38, effectiveTintOpacity)))
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                highlighted ? tint.opacity(0.92) : Color.white.opacity(0.58),
                lineWidth: highlighted ? 2 : 1.5
            )
        }
    }

    private var specularRim: some View {
        shape.strokeBorder(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(reflected(highlighted ? 0.42 : 0.25)), location: 0),
                    .init(color: .white.opacity(reflected(0.10)), location: 0.38),
                    .init(color: .white.opacity(reflected(0.025)), location: 0.72),
                    .init(color: .white.opacity(reflected(highlighted ? 0.18 : 0.08)), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.75
        )
    }

    @ViewBuilder
    private var highlightRim: some View {
        if highlighted {
            shape
                .strokeBorder(tint.opacity(reflected(0.52)), lineWidth: 1)
                .shadow(
                    color: tint.opacity(reflected(0.38)),
                    radius: 4 + (3 * reflectionIntensity)
                )
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlassSurface: some View {
        shape
            .fill(Color.clear)
            .glassEffect(
                .regular
                    .tint(tint.opacity(effectiveTintOpacity))
                    .interactive(isInteractive),
                in: shape
            )
            .overlay(specularRim)
            .overlay(highlightRim)
    }
}
