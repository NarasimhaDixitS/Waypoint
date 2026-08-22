import SwiftUI

/// Full-text search across every task, not just the currently browsed day/week — matches on
/// title or goal name. Selecting a result jumps Today to that task's day, mirroring how Week's
/// expanded task rows navigate (deliberately not opening the edit sheet directly).
struct SearchView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var onSelectTask: (TaskEntity) -> Void

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \TaskEntity.startTime, ascending: true)])
    private var allTasks: FetchedResults<TaskEntity>

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [TaskEntity] {
        guard !trimmedQuery.isEmpty else { return [] }
        return allTasks.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(trimmedQuery)
                || ($0.goal?.name ?? "").localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if trimmedQuery.isEmpty {
                emptyState("Search your tasks by title or goal.")
            } else if results.isEmpty {
                emptyState("No tasks match \u{201C}\(trimmedQuery)\u{201D}.")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(results, id: \.objectID) { task in
                            resultRow(task)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .onAppear { fieldFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ColorTokens.textMuted)
                TextField("Search tasks", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(ColorTokens.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button("Cancel") { dismiss() }
                .foregroundStyle(theme.accentSwatch.color)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func resultRow(_ task: TaskEntity) -> some View {
        Button {
            onSelectTask(task)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(taskDotColor(task))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title ?? "")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .strikethrough(task.isDone)
                        .lineLimit(1)
                    Text("\(task.resolvedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(task.timeRangeLabel)")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorTokens.textMuted)
            }
            .wpCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func taskDotColor(_ task: TaskEntity) -> Color {
        switch task.state {
        case .done: ColorTokens.success
        case .overdue: ColorTokens.warning
        case .future: ColorTokens.scheduled
        case .inProgress: ColorTokens.inProgress
        case .pending: ColorTokens.textMuted
        }
    }
}
