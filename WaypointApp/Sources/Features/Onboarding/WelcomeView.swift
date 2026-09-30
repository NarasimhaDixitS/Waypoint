import SwiftUI
import AuthenticationServices

/// The gate. Nothing in the app is reachable until this is past.
struct WelcomeView: View {
    var onSignIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme

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
                // Apple's own button, not a lookalike — its wording, radius and light/dark
                // behaviour are specified, and a hand-rolled copy is grounds for rejection.
                //
                // Still a placeholder: the real request needs the
                // `com.apple.developer.applesignin` entitlement, which requires a paid
                // Developer Program membership. The overlay swallows the tap so the stub runs
                // rather than a request that would fail; both go away with the entitlement.
                SignInWithAppleButton(.signIn) { _ in
                } onCompletion: { _ in }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                    .overlay {
                        Button(action: onSignIn) {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                Text("Your tasks stay on this device. Signing in is how Waypoint knows the work is yours.")
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
    WelcomeView(onSignIn: {})
}
