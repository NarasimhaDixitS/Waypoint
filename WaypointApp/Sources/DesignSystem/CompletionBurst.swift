import SwiftUI

/// A one-shot completion celebration — a ring pulse plus a handful of particles flung
/// outward from the checkmark — layered on top of `TaskRowView`'s existing bump-scale and
/// haptic. `trigger` is expected to be a monotonically increasing counter (bump it once per
/// completion); every change plays the burst once and settles back to fully invisible,
/// using the same plain `@State` + `.animation` idiom as `TaskRowView`'s own bump, rather
/// than `keyframeAnimator` (which didn't render at all in this overlay position).
struct CompletionBurst: View {
    var trigger: Int
    var color: Color

    @State private var visible = false
    @State private var expanded = false

    private static let offsets: [CGPoint] = [
        CGPoint(x: -10, y: -8),
        CGPoint(x: 1, y: -12),
        CGPoint(x: 11, y: -5),
        CGPoint(x: 9, y: 7),
        CGPoint(x: -2, y: 11),
        CGPoint(x: -11, y: 3),
    ]

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 2)
                .scaleEffect(expanded ? 2.3 : 1)
                .opacity(expanded ? 0 : 0.8)

            ForEach(Array(Self.offsets.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(x: expanded ? point.x : 0, y: expanded ? point.y : 0)
                    .scaleEffect(expanded ? 0.3 : 1)
                    .opacity(expanded ? 0 : 1)
            }
        }
        .frame(width: 26, height: 26)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        // Jump to the "just fired" look with no animation, then animate away on the next
        // runloop turn — collapsing both into one transaction would let SwiftUI skip
        // straight to the end state and animate nothing.
        expanded = false
        visible = true
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.55)) {
                expanded = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            visible = false
            expanded = false
        }
    }
}
