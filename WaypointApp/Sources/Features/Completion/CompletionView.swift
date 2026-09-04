import SwiftUI

struct CompletionView: View {
    @Environment(\.dismiss) private var dismiss

    var streak: Int
    var tasksDone: Int
    var tasksTotal: Int
    var progressBefore: Double?
    var progressAfter: Double?

    @State private var checkScale: CGFloat = 0.3
    @State private var checkOpacity: Double = 0
    @State private var textOffset: CGFloat = 10
    @State private var textOpacity: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle().fill(ColorTokens.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 96)
            .scaleEffect(checkScale)
            .opacity(checkOpacity)

            VStack(spacing: 6) {
                Text("Day complete")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("All \(tasksTotal) tasks done. \(streak)-day streak.")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            .offset(y: textOffset)
            .opacity(textOpacity)

            if let progressBefore, let progressAfter {
                // `Int(_:)` truncates toward zero rather than rounding — a goal with many
                // tasks (say 131) moves well under 1% per task, so truncating silently
                // dropped the after-value's fraction and could show "3% → 3%" for a
                // completion that had actually just crossed into 4%. `.rounded()` first
                // matches what the user actually sees change.
                Text("Goal progress   \(Int((progressBefore * 100).rounded()))% → \(Int((progressAfter * 100).rounded()))%")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(ColorTokens.surface1)
                    .clipShape(Capsule())
                    .opacity(textOpacity)
            }

            Spacer()

            Button("Done", action: { dismiss() })
                .buttonStyle(.wpPrimary)
                .padding(.horizontal, 40)
                .opacity(textOpacity)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.surface0.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) {
                checkScale = 1
                checkOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                textOffset = 0
                textOpacity = 1
            }
        }
        .sensoryFeedback(.success, trigger: checkOpacity) { old, new in new > old }
    }
}

#Preview {
    CompletionView(streak: 6, tasksDone: 5, tasksTotal: 5, progressBefore: 0.70, progressAfter: 0.72)
}
