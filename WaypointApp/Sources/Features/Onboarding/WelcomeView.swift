import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WaypointLogoMark(size: 88)
                .padding(.bottom, 22)

            Text("Waypoint")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Plan your goals. Live your days.")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 10) {
                Button("Continue with Apple", action: onContinue)
                    .buttonStyle(.wpPrimary)

                Button("Continue with email", action: onContinue)
                    .buttonStyle(.wpSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.surface0.ignoresSafeArea())
    }
}

/// The app's mark, from the asset catalogue.
///
/// This used to be drawn here in SwiftUI — a white rounded square, two dark rings and a green
/// dot hardcoded at `0x639922`. Three things were wrong with that: it was the *old* logo, the
/// green was an accent this app retired, and being code rather than an asset meant replacing
/// the icon everywhere else left this one untouched and nobody noticed.
///
/// One image, shared with the launch screen, so there is now a single thing to change.
struct WaypointLogoMark: View {
    var size: CGFloat = 46

    var body: some View {
        Image("LogoMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
