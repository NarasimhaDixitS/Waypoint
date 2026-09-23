import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: AccountManager
    @Environment(\.managedObjectContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDemoConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .wpTypography(.appTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.top, 8)

                accountCard

                VStack(spacing: 0) {
                    row {
                        Text("Appearance").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Picker("", selection: $theme.appearanceMode) {
                            Text("System").tag(AppearanceMode.system)
                            Text("Light").tag(AppearanceMode.light)
                            Text("Dark").tag(AppearanceMode.dark)
                        }
                        .pickerStyle(.menu)
                        .tint(ColorTokens.textSecondary)
                    }
                    divider
                    row {
                        Text("Accent color").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(AccentSwatch.allCases) { swatch in
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle().stroke(ColorTokens.textPrimary, lineWidth: theme.accentSwatch == swatch ? 1.8 : 0)
                                            .padding(-3)
                                    )
                                    .onTapGesture { theme.accentSwatch = swatch }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("\(swatch.rawValue.capitalized) accent")
                                    .accessibilityAddTraits(theme.accentSwatch == swatch ? .isSelected : [])
                            }
                        }
                        .sensoryFeedback(.selection, trigger: theme.accentSwatch)
                    }
                }
                .wpCard(padding: 0)

                VStack(spacing: 0) {
                    NavigationLink {
                        ScheduleSetupView()
                    } label: {
                        row {
                            Text("Recurring schedule").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ColorTokens.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    divider
                    NavigationLink {
                        SleepSetupView(buttonLabel: "Save")
                    } label: {
                        row {
                            Text("Sleep").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ColorTokens.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .wpCard(padding: 0)

                VStack(spacing: 0) {
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Task completion").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                            Text(theme.completionMode.label).wpTypography(.body).foregroundStyle(ColorTokens.textSecondary)
                        }
                        Spacer()
                        Picker("", selection: $theme.completionMode) {
                            Text("Manual").tag(CompletionMode.manual)
                            Text("Auto by time").tag(CompletionMode.autoByTime)
                        }
                        .pickerStyle(.menu)
                        .tint(ColorTokens.textSecondary)
                    }
                    divider
                    row {
                        Text("Notifications").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Toggle("", isOn: $theme.notificationsEnabled)
                            .labelsHidden()
                            .tint(theme.accentSwatch.color)
                    }
                }
                .wpCard(padding: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Developer")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                    Button {
                        showingDemoConfirm = true
                    } label: {
                        row {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Load demo data").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                                Text("Replaces all tasks and goals with a seeded 45-day history")
                                    .wpTypography(.body)
                                    .foregroundStyle(ColorTokens.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ColorTokens.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .wpCard(padding: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
        .confirmationDialog(
            "Replace everything with demo data?",
            isPresented: $showingDemoConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace tasks and goals", role: .destructive) {
                SampleData.loadDemo(into: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every task and goal is deleted and replaced with a seeded demo set. Your commitments and settings are left alone. This can't be undone.")
        }
    }

    private var divider: some View {
        Divider().overlay(ColorTokens.border).padding(.leading, 14)
    }

/// Sign in with Apple, as a placeholder.
    ///
    /// Apple's own `SignInWithAppleButton` is used rather than a lookalike: its wording, corner
    /// radius and light/dark behaviour are specified by Apple and a hand-rolled copy is grounds
    /// for review rejection. It renders without the entitlement — only the *request* needs one —
    /// so this is the real button wired to a stubbed result.
    @ViewBuilder
    private var accountCard: some View {
        if account.isSignedIn {
            VStack(spacing: 0) {
                row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName ?? "Signed in")
                            .wpTypography(.cardTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        if let email = account.email {
                            Text(email)
                                .wpTypography(.body)
                                .foregroundStyle(ColorTokens.textSecondary)
                        }
                    }
                    Spacer()
                }
                divider
                Button { account.signOut() } label: {
                    row {
                        Text("Sign out")
                            .wpTypography(.cardTitle)
                            .foregroundStyle(ColorTokens.warning)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .wpCard(padding: 0)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your account")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                // Honest about what it does today. Promising sync or backup here would be a
                // claim the app can't currently keep.
                Text("Waypoint works fully without an account — everything lives on this device. Signing in is only needed once Waypoint runs somewhere other than your iPhone.")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SignInWithAppleButton(.signIn) { _ in
                    // Placeholder: a real request needs the Apple Developer Program entitlement.
                } onCompletion: { _ in }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .allowsHitTesting(false)
                    .overlay {
                        // Swallows the tap so the stub runs instead of a request that would
                        // fail. Goes away with the entitlement.
                        Button { account.signIn() } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wpCard(padding: 16)
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(14)
        .frame(minHeight: 44)
    }
}
