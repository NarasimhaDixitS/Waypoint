import SwiftUI
import CoreData

struct GoalCreateView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    var onCreated: (GoalEntity) -> Void
    var onRequestPaywall: () -> Void = {}

    @State private var name = ""
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var planningMode: PlanningMode = .manual

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New goal")
                            .wpTypography(.screenTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Text("What are you working toward?")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                    .padding(.top, 12)

                    TextField("e.g. Pass the CFA exam", text: $name)
                        .wpTypography(.cardTitle)
                        .padding(14)
                        .background(ColorTokens.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    DatePicker("Target date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                        .wpTypography(.body)
                        .padding(14)
                        .background(ColorTokens.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text("How should the plan be built?")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)

                    Button {
                        guard theme.isPro else { return }
                        planningMode = .ai
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(planningMode == .ai ? ColorTokens.textInProgress : ColorTokens.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("AI-planned").wpTypography(.cardTitle)
                                    if !theme.isPro { ProBadge() }
                                }
                                Text("Describe your routine, AI builds daily tasks")
                                    .wpTypography(.body)
                                    .foregroundStyle(ColorTokens.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(planningMode == .ai ? ColorTokens.inProgressTint : ColorTokens.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(planningMode == .ai ? ColorTokens.inProgress : Color.clear, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(theme.isPro ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        planningMode = .manual
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "pencil")
                                .foregroundStyle(planningMode == .manual ? ColorTokens.textPrimary : ColorTokens.textSecondary)
                            Text("I'll plan it myself")
                                .wpTypography(.cardTitle)
                                .foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .background(ColorTokens.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(planningMode == .manual ? ColorTokens.textPrimary : Color.clear, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(ColorTokens.surface0.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createGoal() }
                        .tint(theme.accentSwatch.color)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createGoal() {
        let goal = GoalEntity.create(in: context, name: name, targetDate: targetDate, planningMode: planningMode)
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
