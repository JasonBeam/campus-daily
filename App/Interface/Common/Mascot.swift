import SwiftUI

/// The orange droplet mascot with its one-time hop; the shape lives in Shared/MascotShape.swift.
struct Mascot: View {
    var size: CGFloat = 52
    /// Play the hop once on appear (disabled under Reduce Motion).
    var hops = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    var body: some View {
        MascotGlyph(size:size, color:Theme.accent)
        .offset(y:phase == 0 ? 14 : phase == 1 ? -4 : 0)
        .scaleEffect(phase == 0 ? 0.7 : phase == 1 ? 1.04 : 1)
        .opacity(phase == 0 ? 0 : 1)
        .accessibilityHidden(true)
        .task {
            guard hops, !reduceMotion else { phase = 2; return }
            let spring = Animation.spring(response:0.5, dampingFraction:0.55)
            withAnimation(spring) { phase = 1 }
            try? await Task.sleep(for:.milliseconds(220))
            withAnimation(spring) { phase = 2 }
        }
    }
}
