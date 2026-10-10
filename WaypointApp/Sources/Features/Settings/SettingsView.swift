import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @Environment(\.managedObjectContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    #if DEBUG
    @State private var showingDemoConfirm = false
    @State private var showingFreshConfirm = false
    @State private var storeDiagnosis = "asking the store…"
    #endif
    /// Confirms the tap landed. The notes themselves won't reappear until the situation each
    /// one explains comes round again, so without this the button looks like it did nothing.
    @State private var tipsReset = false
    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Waypoint \(version) (\(build))"
    }

    @State private var showingMailComposer = false
    /// Shown when there's no Mail account to hand the draft to, which `canSendMail` reports
    /// and nothing else can fix — so the address is offered as text instead of a dead button.
    @State private var showingMailFallback = false
    @State private var showingPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .wpTypography(.appTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.top, 8)

                subscriptionCard
                manageSubscriptionRow

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
                    divider
                    // The first-run notes are one-shot by design, which makes them impossible
                    // to find again the moment they're dismissed — including by someone who
                    // dismissed one by accident reaching for something else.
                    Button {
                        FirstRunHint.resetAll()
                        tipsReset = true
                    } label: {
                        row {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show tips again").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                                Text(tipsReset ? "They'll appear next time each one applies" : "Brings back the one-off explanations")
                                    .wpTypography(.micro)
                                    .foregroundStyle(tipsReset ? theme.accentSwatch.markColor : ColorTokens.textSecondary)
                            }
                            Spacer()
                            Image(systemName: tipsReset ? "checkmark" : "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(tipsReset ? theme.accentSwatch.markColor : ColorTokens.textMuted)
                        }
                    }
                    .buttonStyle(.wpRow)
                    divider
                    // Hands the draft to Mail rather than posting it anywhere. See `Feedback`
                    // for why: an app can't hold a mail-provider API key, and a form with a
                    // mandatory email field would collect contact information — which this
                    // app's privacy label currently, truthfully, says it doesn't.
                    Button {
                        if Feedback.canSend {
                            showingMailComposer = true
                        } else {
                            showingMailFallback = true
                        }
                    } label: {
                        row {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send feedback").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                                Text("Opens your mail app — nothing is sent from here")
                                    .wpTypography(.micro)
                                    .foregroundStyle(ColorTokens.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ColorTokens.textMuted)
                        }
                    }
                    .buttonStyle(.wpRow)
                }
                .wpCard(padding: 0)

                yourDataCard

                // Debug builds only. Everything in here is destructive or dishonest in a
                // tester's hands: "Load demo data" deletes every task and goal they own, and
                // the state buttons hand out a paid subscription for nothing. Useful on a
                // development device, indefensible on anyone else's.
                #if DEBUG
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
                        // Was `purchase(.annual)`, which on a simulator with no App Store
                        // account simply fails — so the one state the panel exists to show was
                        // the one it couldn't reach.
                        stateButton("Renewing", isCurrent: subscription.isPreviewing(.renewing)) { subscription.preview(.renewing) }
                        stateButton("Cancelled", isCurrent: subscription.isPreviewing(.cancelled)) { subscription.preview(.cancelled) }
                        stateButton("Card failed", isCurrent: subscription.isPreviewing(.billingProblem)) { subscription.preview(.billingProblem) }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Store").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                        Text(storeDiagnosis)
                            .wpTypography(.micro)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .task {
                        storeDiagnosis = await Store.diagnosis()
                        // Also written out so it can be read without scrolling to it.
                        UserDefaults.standard.set(storeDiagnosis, forKey: "debug.storeDiagnosis")
                    }
                    divider
                    Button {
                        showingFreshConfirm = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset to a new install").wpTypography(.cardTitle).foregroundStyle(ColorTokens.textPrimary)
                                Text("Everything gone, including the trial clock")
                                    .wpTypography(.micro)
                                    .foregroundStyle(ColorTokens.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ColorTokens.textMuted)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.wpRow)
                    divider
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
                #endif
                // The one line every bug report needs and nobody can find. Added because the
                // feedback fallback told people to quote their build, and there was nowhere
                // on this screen to read it.
                Text(versionLine)
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, ColorTokens.tabBarClearance)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear {
            #if DEBUG
            // `-wpPaywall`. The paywall is three taps deep and its prices now come off the
            // network, so "did the store answer" is a question only the real screen can settle.
            if ProcessInfo.processInfo.arguments.contains("-wpPaywall") { showingPaywall = true }
            #endif
        }
        .sheet(isPresented: $showingMailComposer) { MailComposer() }
        .confirmationDialog(
            "No mail account set up",
            isPresented: $showingMailFallback,
            titleVisibility: .visible
        ) {
            Button("Copy \(Feedback.address)") {
                UIPasteboard.general.string = Feedback.address
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Write to \(Feedback.address) from wherever you read mail. Including which build you're on helps — it's in Settings at the bottom of this screen.")
        }
        // Inside the guard, with the button that raises it. It sat outside, so a Release
        // binary carried "Replace everything with demo data?" and a call to
        // `SampleData.loadDemo` — unreachable, because the only thing that sets
        // `showingDemoConfirm` is the DEBUG-only button, but shipped all the same. Two ways
        // that matters: anyone running `strings` on the App Store binary reads a sentence
        // about wiping their data, and the next person to add a second setter gets a live
        // destructive dialog in production without touching this file.
        #if DEBUG
        .confirmationDialog(
            "Reset to a new install?",
            isPresented: $showingFreshConfirm,
            titleVisibility: .visible
        ) {
            Button("Wipe everything", role: .destructive) {
                FreshInstall.wipe(in: context)
                // The trial clock restarts the moment anything asks again, so this has to be
                // the last word — otherwise the next read re-begins it before the app relaunches
                // and the first run starts on day one of a trial that was never reset.
                exit(0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every task, goal, commitment and setting, and clears the trial from the Keychain — the one thing deleting the app doesn't. Waypoint will quit; reopen it to see the first run.")
        }
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
        #endif
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

    /// What having no server actually costs the person using the app, said plainly.
    ///
    /// **Not a disclaimer.** Waypoint keeps everything on the device, which is why its privacy
    /// label can say what it says — but the same fact means a new iPhone set up from scratch
    /// starts empty, and somebody deserves to learn that before they're standing in a shop
    /// rather than after. The fix is one sentence of advice and it genuinely works: a direct
    /// transfer during setup copies the app's storage wholesale, with no dependence on iCloud
    /// Backup being switched on or on there being room in a 5GB account.
    ///
    /// The subscription line is here because it is the thing people actually worry about, and
    /// the answer is reassuring: it belongs to the Apple Account, not to the handset.
    private var yourDataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your data is on this iPhone")
                .wpTypography(.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            Text("There's no account and no server, so nothing you write here leaves the device.")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Getting a new iPhone? Transfer straight from your old one while setting it up, or restore it from a backup, and your tasks and history come with it. Your subscription is tied to your Apple Account, so that always comes back — tap Restore Purchases if it doesn't.")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .wpCard(padding: 0)
    }

    /// The route to Apple's own subscription management, which is the only place a plan can
    /// actually be cancelled, resumed, or have its payment method changed.
    ///
    /// Shown whenever there is a subscription at all — including cancelled and payment-problem,
    /// which are the two states somebody is most likely to be hunting for it from.
    @ViewBuilder private var manageSubscriptionRow: some View {
        if case .subscribed = subscription.status {
            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            } label: {
                row {
                    Text("Manage subscription")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }
            .buttonStyle(.plain)
            .wpCard(padding: 0)
        }
    }

    private var subscriptionTitle: String {
        switch subscription.status {
        case .trial: return "Free trial"
        case .subscribed(let plan, _, _): return "Waypoint \(plan.title)"
        case .free: return "Trial ended"
        }
    }

    private var subscriptionStateName: String {
        switch subscription.status {
        case .trial(let daysLeft): "trial, \(daysLeft)d left"
        case .subscribed(_, _, let renewal):
            switch renewal {
            case .renewing: "subscribed, renewing"
            case .cancelled: "subscribed, cancelled"
            case .billingProblem: "subscribed, card failed"
            }
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
            return daysLeft == 1 ? "Last day — tap to subscribe" : "\(daysLeft) days left — tap to subscribe"
        case .subscribed(_, let until, let renewal):
            let date = until.formatted(.dateTime.day().month(.abbreviated).year())
            switch renewal {
            case .renewing: return "Renews \(date)"
            // Never the word "renews" here. Somebody who has just cancelled opens this screen
            // precisely to check that it took.
            case .cancelled: return "Ends \(date) · won't renew"
            case .billingProblem: return "Payment problem — update your payment method"
            }
        case .free:
            return "Today and your history stay free. Subscribe to plan ahead, see the week and track progress."
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
