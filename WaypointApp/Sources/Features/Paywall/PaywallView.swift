import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    private let features = [
        "AI goal breakdown and daily planning",
        "Smart priority and adhoc-swap suggestions",
        "Task notes",
        "Progress analytics and insights",
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ColorTokens.inProgressTint)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(ColorTokens.inProgress)
                )

            VStack(spacing: 4) {
                Text("Waypoint Pro")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Let AI plan your days for you.")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 10) {
                        Circle().fill(ColorTokens.success).frame(width: 7, height: 7)
                        Text(feature)
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                Button("Start free trial") {
                    theme.isPro = true
                    dismiss()
                }
                .buttonStyle(.wpPrimary)

                Button("Continue with free plan") { dismiss() }
                    .buttonStyle(.plain)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.surface0.ignoresSafeArea())
    }
}

#Preview {
    PaywallView().environmentObject(ThemeManager.shared)
}
