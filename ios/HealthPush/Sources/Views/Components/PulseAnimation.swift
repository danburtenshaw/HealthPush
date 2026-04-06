import SwiftUI

// MARK: - PulseAnimation

/// A subtle pulsing circle animation used to indicate an active sync.
///
/// This view renders concentric expanding circles with fading opacity,
/// creating a "radar pulse" effect.
struct PulseAnimation: View {

    // MARK: Properties

    let color: Color
    let isAnimating: Bool

    @State private var scale1: CGFloat = 0.5
    @State private var opacity1: Double = 0.8
    @State private var scale2: CGFloat = 0.5
    @State private var opacity2: Double = 0.8

    // MARK: Body

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(color.opacity(opacity1))
                .scaleEffect(scale1)

            // Inner pulse ring
            Circle()
                .fill(color.opacity(opacity2))
                .scaleEffect(scale2)

            // Center dot
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
        .onChange(of: isAnimating, initial: true) { _, animating in
            if animating {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    // MARK: Animation

    private func startAnimation() {
        withAnimation(
            .easeOut(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            scale1 = 1.0
            opacity1 = 0.0
        }

        withAnimation(
            .easeOut(duration: 1.5)
            .repeatForever(autoreverses: false)
            .delay(0.5)
        ) {
            scale2 = 1.0
            opacity2 = 0.0
        }
    }

    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            scale1 = 0.5
            opacity1 = 0.0
            scale2 = 0.5
            opacity2 = 0.0
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        PulseAnimation(color: .green, isAnimating: true)
        PulseAnimation(color: .blue, isAnimating: true)
        PulseAnimation(color: .red, isAnimating: false)
    }
}
