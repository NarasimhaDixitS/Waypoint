import SwiftUI
import CoreData

struct GoalCreateView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    var onCreated: (GoalEntity) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
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
            planningMode: .manual,
            notes: description.isEmpty ? nil : description
        )
        try? context.save()
        onCreated(goal)
        dismiss()
    }
}
