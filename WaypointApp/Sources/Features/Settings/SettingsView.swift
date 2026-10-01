import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @Environment(\.managedObjectContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDemoConfirm = false
    @State private var showingPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .wpTypography(.appTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.top, 8)

                accountCard
                subscriptionCard

                VStack(spacing: 0) {
                    // Both of these are gone in paper rather than disabled. The first attempt
                    // greyed them out on the reasoning that a control which vanishes makes
                    // people wonder what they broke — but that only holds when the absence is
                    // unexplained. The Display row says "no light or dark" and "paper uses ink"
                    // right where they used to be, so keeping two dead controls around is just
                    // clutter standing in for an explanation that's already there.
                    if theme.palette != .paper {
                        row {
                            Text("Appearance").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                            Spacer(minLength: 8)
                            Picker("", selection: $theme.appearanceMode) {
                                Text("System").tag(AppearanceMode.system)
                                Text("Light").tag(AppearanceMode.light)
                                Text("Dark").tag(AppearanceMode.dark)
                            }
                            .pickerStyle(.menu)
                            .tint(ColorTokens.textSecondary)
                        }
                        divider
                    }
                    // Its own row, directly under Appearance, because it is the second half of
                    // the same question. Light/dark is *when* you're reading; this is *how*.
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Display").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                            Text(theme.palette.detail)
                                .wpTypography(.body)
                                .foregroundStyle(ColorTokens.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Picker("", selection: $theme.palette) {
                            ForEach(Palette.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(ColorTokens.textSecondary)
                    }
                    if theme.palette != .paper {
                    divider
                    // Swatches on their own row rather than trailing the label. Eight of them
                    // beside a title overflowed the card, and the row would silently get
                    // tighter every time an accent was added.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent color").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                        HStack(spacing: 0) {
                            ForEach(AccentSwatch.allCases) { swatch in
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle().stroke(ColorTokens.textPrimary, lineWidth: theme.accentSwatch == swatch ? 2 : 0)
                                            .padding(-3.5)
                                    )
                                    // 44pt target around a 24pt dot — the dot is the mark, the
                                    // tappable area is what a finger actually needs.
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) { theme.accentSwatch = swatch }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("\(swatch.label) accent")
                                    .accessibilityAddTraits(theme.accentSwatch == swatch ? .isSelected : [])
                            }
                        }
                        .sensoryFeedback(.selection, trigger: theme.accentSwatch)
                    }
                    // `row`'s own padding, restated: this section is a column now, not a row.
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
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
                        // A master switch, not the thing that turns reminders on. It used to be
                        // both — flipping it reminded you about every task on today's list — and
                        // the label said "Notifications" either way. Reminders are now armed per
                        // task; this only decides whether any of them, plus the day summary and
                        // streak nudge, are allowed to arrive at all.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                            Text("Reminders are set per task")
                                .wpTypography(.micro)
                                .foregroundStyle(ColorTokens.textSecondary)
                        }
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
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subscription state").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                            // Waiting two weeks is not a testing strategy. All three states are
                            // reachable from here because all three have to be *looked* at —
                            // the free tier blurs whole screens, and nothing about that can be
                            // judged from reading the gate that produces it.
                            Text("Currently: \(subscriptionStateName). Switch to any state.")
                                .wpTypography(.body)
                                .foregroundStyle(ColorTokens.textSecondary)
                        }
                        Spacer()
                    }
                    .wpCard(padding: 0)

                    HStack(spacing: 10) {
                        stateButton("Trial", isCurrent: subscription.status.isTrial) { subscription.resetTrial() }
                        stateButton("Free tier", isCurrent: !subscription.status.hasFullAccess) { subscription.expireNow() }
                        stateButton("Subscribed", isCurrent: subscription.status.isSubscribed) { subscription.purchase(.annual) }
                    }

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
            .padding(.bottom, ColorTokens.tabBarClearance)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
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

private var subscriptionCard: some View {
        Button { showingPaywall = true } label: {
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionTitle)
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text(subscriptionDetail)
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorTokens.textMuted)
            }
        }
        .buttonStyle(.plain)
        .wpCard(padding: 0)
    }

    private var subscriptionTitle: String {
        switch subscription.status {
        case .trial: "Free trial"
        case .subscribed(let plan, _): "Waypoint \(plan.title)"
        case .free: "Trial ended"
        }
    }

    private var subscriptionStateName: String {
        switch subscription.status {
        case .trial(let daysLeft): "trial, \(daysLeft)d left"
        case .subscribed: "subscribed"
        case .free: "free tier"
        }
    }

    /// The current state is marked rather than merely available. Three buttons that all look
    /// identical make it very easy to test the state you were already in and conclude the gate
    /// works, which is the one mistake this panel exists to prevent.
    private func stateButton(_ label: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .wpTypography(.body)
                .foregroundStyle(isCurrent ? ColorTokens.surface0 : ColorTokens.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isCurrent ? ColorTokens.textPrimary : ColorTokens.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var subscriptionDetail: String {
        switch subscription.status {
        case .trial(let daysLeft):
            daysLeft == 1 ? "Last day — tap to subscribe" : "\(daysLeft) days left — tap to subscribe"
        case .subscribed(_, let renewsAt):
            "Renews \(renewsAt.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .free:
            "Today and your history stay free. Subscribe to plan ahead, see the week and track progress."
        }
    }

/// The signed-in state only.
    ///
    /// There's no sign-in button here any more: the welcome screen gates the whole app, so by
    /// the time anyone reaches Settings they're signed in by definition. Signing out drops
    /// straight back to that gate, which is why this doesn't need the other half.
    @ViewBuilder
    private var accountCard: some View {
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
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { account.signOut() }
            } label: {
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
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(14)
        .frame(minHeight: 44)
    }
}
