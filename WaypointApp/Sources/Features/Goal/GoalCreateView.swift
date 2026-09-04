import SwiftUI
import CoreData

struct GoalCreateView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    var onCreated: (GoalEntity) -> Void
    var onRequestPaywall: () -> Void = {}

    @State private var name = ""
    @State private var description = ""
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var planningMode: PlanningMode = .manual
    @State private var showingDateSheet = false

    /// Same flat, borderless "inset well" as the task editor: `surface0` (the page-background
    /// gray) fills the field, sitting inside the card's own `surface1`. See `NewTaskView`.
    @ViewBuilder
    private func filledField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(ColorTokens.surface0)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var header: some View {
        ZStack {
            Text("New Goal")
                .wpTypography(.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ColorTokens.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            filledField {
                TextField("e.g. Pass the CFA exam", text: $name)
                    .wpTypography(.cardTitle)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            filledField {
                TextField("Add a description", text: $description, axis: .vertical)
                    .wpTypography(.body)
                    .lineLimit(1...4)
            }
        }
    }

    private var targetDateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target date")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            Button { showingDateSheet = true } label: {
                filledField {
                    HStack {
                        Text(targetDate.formatted(.dateTime.month(.abbreviated).day().year()))
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Same segmented capsule as the task editor's Priority row — both options visible, tap to
    /// choose. The per-mode explanation moves to a caption underneath, since a segment is too
    /// narrow to carry it and only the selected one's description is worth reading.
    private var planningRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planning")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            HStack(spacing: 4) {
                planningSegment(.manual, label: "I'll plan it")
                planningSegment(.ai, label: "AI-planned")
            }
            .padding(4)
            .background(ColorTokens.surface0)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(planningMode == .ai
                 ? "Describe your routine, AI builds daily tasks."
                 : "You'll add the tasks yourself.")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
                .contentTransition(.opacity)
        }
        .sensoryFeedback(.selection, trigger: planningMode)
    }

    private func planningSegment(_ mode: PlanningMode, label: String) -> some View {
        let selected = planningMode == mode
        let locked = mode == .ai && !theme.isPro
        return HStack(spacing: 5) {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if locked { ProBadge() }
        }
        .wpTypography(.body)
        .foregroundStyle(selected ? ColorTokens.textPrimary : ColorTokens.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? ColorTokens.surface1 : Color.clear)
                .shadow(color: selected ? ColorTokens.shadowResting : .clear, radius: 4, x: 0, y: 2)
        )
        .opacity(locked ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            // Pro-gated: leave the selection alone and let the parent decide how to pitch it,
            // rather than silently doing nothing on tap.
            guard !locked else {
                onRequestPaywall()
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) { planningMode = mode }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ColorTokens.surface0)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                createGoal()
            } label: {
                Text("Create")
                    .wpTypography(.cardTitle)
                    // Inverts with `textPrimary` rather than being a hardcoded `.white` — see
                    // the Save button in `NewTaskView`.
                    .foregroundStyle(ColorTokens.surface0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ColorTokens.textPrimary)
                    .clipShape(Capsule())
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameField
                    descriptionField
                    targetDateField
                    planningRow
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(16)
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface0)
        .sheet(isPresented: $showingDateSheet) {
            DatePickerSheet(date: $targetDate, notBefore: .now)
        }
    }

    private func createGoal() {
        let goal = GoalEntity.create(
            in: context,
            name: name,
            targetDate: targetDate,
            planningMode: planningMode,
            notes: description.isEmpty ? nil : description
        )
        if planningMode == .ai {
            AIPlanningStub.generateDailyTasks(for: goal, in: context)
        }
        try? context.save()
        onCreated(goal)
        dismiss()
    }
}

/// Local stand-in for the Claude-API-backed goal breakdown described in the spec.
/// Produces a placeholder daily task per day so the Pro flow is demonstrable offline;
/// swap for a real call to the backend's goal-breakdown endpoint later.
enum AIPlanningStub {
    static func generateDailyTasks(for goal: GoalEntity, in context: NSManagedObjectContext) {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        let dayCount = max(cal.dateComponents([.day], from: start, to: goal.resolvedTargetDate).day ?? 0, 1)
        for offset in 0..<min(dayCount, 60) {
            let day = cal.date(byAdding: .day, value: offset, to: start)!
            let startTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            TaskEntity.create(
                in: context,
                title: "\(goal.name ?? "Goal") – step \(offset + 1)",
                date: day,
                startTime: startTime,
                durationMinutes: 45,
                priority: offset % 5 == 0 ? .high : .medium,
                goal: goal
            )
        }
    }
}

#Preview {
    GoalCreateView(onCreated: { _ in })
        .environmentObject(ThemeManager.shared)
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).container.viewContext)
}
