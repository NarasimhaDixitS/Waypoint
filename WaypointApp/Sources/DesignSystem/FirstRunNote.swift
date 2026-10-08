import SwiftUI

/// A one-time explanation, shown where and when the thing it explains first happens.
///
/// **Deliberately not a guided tour.** A spotlight sequence explains the interface at the one
/// moment the user has no problem to attach the explanation to, and it has to know where every
/// element sits — which in a month of moving tab icons, inserting a tab and rebuilding the day
/// timeline would have left it pointing confidently at empty space, with nothing failing to say
/// so. These appear next to the thing itself, when it turns up, and then never again.
///
/// **Each note owns its own flag.** No coordinator, no sequence, no ordering to keep straight:
/// a note is a view that either draws itself or doesn't. Adding one is one view and one case,
/// and deleting one leaves nothing behind.
///
/// They explain *rules*, not controls. "Tap + to add a task" is a caption for a button anyone
/// can already see; "a missed task can't be ticked off later" is the thing that surprises
/// people, and the surprise is the whole reason to say it.
enum FirstRunHint: String, CaseIterable {
    /// Completion is locked to a task's own day, so an overdue row's checkbox is disabled.
    /// Startling the first time, and entirely deliberate.
    case overdueIsLocked
    /// What the goals tab is, the first time there's a goal to look at.
    case goalCentre

    var storageKey: String { "firstRunHint.\(rawValue)" }

    /// Used by Settings' "Show tips again".
    ///
    /// Clears the Progress tab's news too. Both are the same promise from the user's side —
    /// "show me the things you only show once" — and a reset that brought back two of them and
    /// quietly left the third is the kind of half-answer that makes a button look broken.
    static func resetAll() {
        for hint in allCases {
            UserDefaults.standard.removeObject(forKey: hint.storageKey)
        }
        ProgressNews.reset()
    }
}

struct FirstRunNote: View {
    @EnvironmentObject private var theme: ThemeManager
    @AppStorage private var dismissed: Bool

    private let message: String

    init(_ hint: FirstRunHint, _ message: String) {
        self.message = message
        _dismissed = AppStorage(wrappedValue: false, hint.storageKey)
    }

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accentSwatch.markColor)
                    .padding(.top, 1)

                Text(message)
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ColorTokens.textMuted)
                        // 44pt of target around an 11pt glyph, reaching outwards so the note
                        // doesn't grow a row's worth of padding to hold it.
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -6)
                .padding(.top, -4)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ColorTokens.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ColorTokens.border, lineWidth: 1)
                    )
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
