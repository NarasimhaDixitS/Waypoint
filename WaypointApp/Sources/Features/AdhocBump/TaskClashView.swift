import SwiftUI

/// What to do when a task won't fit where it was put.
///
/// The sheet this replaces opened on a warning triangle and a paragraph of prose, then asked you
/// to pick a radio button from a list of your own tasks before its main button would even
/// enable. Three things were wrong with that, and they're worth separating:
///
/// - **It never showed what you were trying to do.** The task being created was described in a
///   sentence, never shown. You were asked to resolve a collision between one thing you could
///   see and one you had to remember.
/// - **It led with sacrifice.** The primary action was "move one of your existing tasks to
///   tomorrow", which is the most destructive option available and almost never the one wanted.
///   Most days aren't full — they're full *at two o'clock* — so the useful answer is nearly
///   always another time, and that was buried as a single take-it-or-leave-it suggestion.
/// - **It asked before it explained.** A radio list of tasks appeared above any statement of
///   what was actually in the way.
///
/// So this one is ordered the other way round: here is what you're adding, here is what it runs
/// into, and now here are the ways out — cheapest first.
struct TaskClashView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    /// What the person is trying to do, shown rather than described.
    let subjectTitle: String
    let subjectRange: String
    /// What's in the way. More than one is normal when a long task is dropped across a busy
    /// stretch.
    let conflicts: [TaskEntity]
    /// Times that would actually fit, nearest first. Empty on a genuinely full day, and empty
    /// for an edit, where the time is the thing being chosen deliberately.
    let slots: [ScheduleEngine.OpenSlot]
    var onPickSlot: (Date) -> Void
    var onBumpConflicts: ([TaskEntity]) -> Void
    var onCancel: () -> Void = {}

    @State private var detent: PresentationDetent = .large
    @State private var contentHeight: CGFloat = 0

    /// The sheet's own chrome around the scrolling content — the outer inset, top and bottom.
    private static let chrome: CGFloat = 32


    private var conflictSummary: String {
        guard let first = conflicts.first else { return "" }
        return conflicts.count == 1
            ? "“\(first.title ?? "A task")”"
            : "\(conflicts.count) tasks"
    }

    var body: some View {
        // Scrolling, not stretching. A sheet with fixed content does two bad things across the
        // two detents it offers: at `.medium` it *compresses*, which squeezed the bump button's
        // label onto one line and truncated the task name it exists to name; at `.large` the
        // slack had to go somewhere and the cards grew to absorb it, leaving a rail stretched
        // down an inch of empty space. A scroll view gives its content the height it asks for
        // and keeps the remainder, so neither happens — and a genuinely long task title now
        // scrolls instead of being cut off.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("That time is taken")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.bottom, 18)

                card(title: subjectTitle, detail: subjectRange, tint: theme.accentSwatch.markColor)

                // A word, not an icon. "Overlaps" is the entire explanation, and it belongs
                // between the two things it describes rather than in a paragraph above them.
                Text("overlaps")
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textMuted)
                    .padding(.vertical, 8)
                    .padding(.leading, 4)

                VStack(spacing: 8) {
                    ForEach(conflicts, id: \.objectID) { task in
                        card(
                            title: task.title ?? "Untitled",
                            detail: "\(task.timeRangeLabel) · \(task.priorityValue.label) priority",
                            tint: ColorTokens.warning
                        )
                    }
                }

                if !slots.isEmpty {
                    label("MOVE IT TO")
                    // Horizontal, because these are a handful of short times and a stack of
                    // full-width rows would make three options look like a form to fill in.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(slots) { slot in
                                Button {
                                    onPickSlot(slot.start)
                                    dismiss()
                                } label: {
                                    Text(slot.start.formatted(.dateTime.hour().minute()))
                                        .wpTypography(.cardTitle)
                                        .foregroundStyle(ColorTokens.surface0)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                        .background(ColorTokens.textPrimary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                label(slots.isEmpty ? "OR" : "OR, IF IT HAS TO BE THEN")

                VStack(spacing: 10) {
                    actionButton("Move \(conflictSummary) to tomorrow") {
                        // Every conflict, not one of them. The old sheet moved a single chosen
                        // task and then saved regardless, so dropping something across two tasks
                        // left one still overlapping — a collision resolver that collides.
                        onBumpConflicts(conflicts)
                        dismiss()
                    }
                    actionButton("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .padding(22)
            // Clear of the drag indicator, which sits at the sheet's own top edge and ran
            // straight through the title at the default inset.
            .padding(.top, 10)
            .background {
                GeometryReader { proxy in
                    // Written straight to state rather than through a `PreferenceKey`. The
                    // preference version reported zero and never updated — measuring a view
                    // inside a scroll view that way doesn't settle — and a sheet sized from
                    // zero silently falls back to filling the screen, which looks like the
                    // measurement working and isn't.
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(16)
        // Sized to its own content, not to one of Apple's two stock fractions.
        //
        // `.medium` cut the last two buttons off — including Cancel, and a sheet whose way out
        // is below the fold is a sheet that traps people. `.large` showed everything and left
        // two thirds of the screen blank underneath. Neither is a property of this sheet; both
        // are what happens when a fixed fraction meets content whose height depends on how long
        // a task is called and how many things it clashed with. Measuring means it fits in both
        // directions: a long title makes it taller, one conflict keeps it short.
        //
        // `.large` stays in the set as the ceiling, for content taller than the screen — the
        // scroll view handles the overflow from there.
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + Self.chrome), .large] : [.large], selection: $detent)
        .onChange(of: contentHeight) { _, height in
            guard height > 0 else { return }
            detent = .height(height + Self.chrome)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface0)
    }

    /// A fill *and* a border, which is what the app's secondary buttons have always been.
    ///
    /// Two goes at this were wrong in the same way. The shared `.wpSecondary` style fills with
    /// `surface1` — exactly the token this sheet uses for its own background — so the buttons
    /// were same-on-same. Swapping the fill to `surface0` fixed the token but not the problem:
    /// in light mode those two are `#FFFFFF` and `#F5F5F3`, a four percent difference, which is
    /// a fill you can prove exists and nobody can see.
    ///
    /// The border is what actually makes a button read as one at that contrast, and dropping it
    /// was the real mistake — `.wpSecondary` has always carried one. This is the same recipe
    /// inverted for an inverted background: recessed fill, visible edge.
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .wpTypography(.body)
                .fontWeight(.medium)
                .foregroundStyle(ColorTokens.textPrimary)
                // Two lines, then truncate. Task titles have no length limit, and the whole
                // point of this button is naming the one being moved.
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .background(ColorTokens.surface0)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ColorTokens.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .wpTypography(.micro)
            .foregroundStyle(ColorTokens.textMuted)
            .tracking(0.6)
            .padding(.top, 20)
            .padding(.bottom, 10)
            .padding(.leading, 4)
    }

    /// The rail is an overlay rather than a sibling in an HStack.
    ///
    /// As a sibling it was a `RoundedRectangle` with a width and no height, which makes it
    /// infinitely greedy vertically — so whenever the sheet had slack to distribute, the card
    /// took it and the rail drew a line down an inch of nothing. An overlay can only be as tall
    /// as what it sits on, and what it sits on is sized by its text.
    private func card(title: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .wpTypography(.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
                .lineLimit(2)
            Text(detail)
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
        }
        .padding(.vertical, 14)
        .padding(.trailing, 14)
        .padding(.leading, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.surface0)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
