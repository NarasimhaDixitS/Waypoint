import SwiftUI

/// The gate. Nothing in the app is reachable until this is past.
struct WelcomeView: View {
    var onContinue: () -> Void


    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WaypointLogoMark(size: 96)
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

            VStack(spacing: 12) {
                // Was a Sign in with Apple button that signed nobody in — it called a stub
                // hardcoding one name and address, so every person who installed the app
                // became the developer. Nothing here ever needed an identity: the tasks are in
                // a local database, and once purchases arrive they are tied to the buyer's
                // Apple ID by the App Store, not by anything this app stores.
                //
                // The screen stays because it is the only place the app introduces itself.
                // Only the claim goes.
                Button(action: onContinue) {
                    Text("Get started")
                }
                .buttonStyle(.wpPrimary)

                Text("Everything you plan stays on this device. No account, nothing to sign up for.")
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.surface0.ignoresSafeArea())
    }
}

/// The app's mark — the icon itself, corners and all, rather than the bare disc inside it.
///
/// The badge is what someone tapped to get here, so it's the shape they recognise. iOS masks
/// the icon's corners at display time and the file is a full square, so the rounding is
/// re-applied here.
struct WaypointLogoMark: View {
    var size: CGFloat = 46

    var body: some View {
        Image("LogoBadge")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: ColorTokens.shadowResting, radius: 12, x: 0, y: 6)
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
