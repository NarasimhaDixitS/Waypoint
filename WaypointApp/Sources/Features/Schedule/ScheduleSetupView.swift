import SwiftUI

struct ScheduleSetupView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CommitmentEntity.createdAt, ascending: true)])
    private var commitments: FetchedResults<CommitmentEntity>

    @State private var showingAdd = false
    @State private var editingCommitment: CommitmentEntity?
    @State private var pendingDeletion: CommitmentEntity?
    var onFinished: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your schedule")
                            .wpTypography(.screenTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Text("So Waypoint can plan around real life.")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 10) {
                        ForEach(commitments) { commitment in
                            Button {
                                editingCommitment = commitment
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(commitment.name ?? "")
                                            .wpTypography(.cardTitle)
                                            .foregroundStyle(ColorTokens.textPrimary)
                                        Text(commitment.timeRangeLabel)
                                            .wpTypography(.body)
                                            .foregroundStyle(ColorTokens.textSecondary)
                                    }
                                    Spacer()
                                    Button {
                                        pendingDeletion = commitment
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundStyle(ColorTokens.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete \(commitment.name ?? "commitment")")
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ColorTokens.textMuted)
                                }
                                .wpCard()
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            showingAdd = true
                        } label: {
                            Text("+ Add a commitment")
                                .wpTypography(.cardTitle)
                                .foregroundStyle(ColorTokens.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(ColorTokens.border, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            if let onFinished {
                Button("Continue", action: onFinished)
                    .buttonStyle(.wpPrimary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationTitle(onFinished == nil ? "Schedule" : "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            CommitmentEditorSheet(existing: nil)
        }
        .sheet(item: $editingCommitment) { commitment in
            CommitmentEditorSheet(existing: commitment)
        }
        .confirmationDialog(
            "Delete this commitment?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion {
                    context.delete(pendingDeletion)
                    try? context.save()
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
    }
}

private struct CommitmentEditorSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let existing: CommitmentEntity?

    @State private var name: String
    @State private var icon: String
    @State private var selectedDays: Set<String>
    @State private var startTime: Date
    @State private var endTime: Date

    private let iconOptions = ["work", "gym", "class", "meeting", "sleep", "custom"]

    init(existing: CommitmentEntity?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon ?? "work")
        _selectedDays = State(initialValue: existing.map { Set($0.dayList) } ?? ["Mon", "Tue", "Wed", "Thu", "Fri"])
        _startTime = State(initialValue: existing?.resolvedStartTime ?? Self.defaultTime(9, 0))
        _endTime = State(initialValue: existing?.resolvedEndTime ?? Self.defaultTime(17, 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Work", text: $name)
                }
                Section("Icon") {
                    Picker("Icon", selection: $icon) {
                        ForEach(iconOptions, id: \.self) { key in
                            Text(key.capitalized).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Days") {
                    HStack {
                        ForEach(CommitmentEntity.weekdaySymbols, id: \.self) { day in
                            let selected = selectedDays.contains(day)
                            Text(String(day.prefix(1)))
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(selected ? ColorTokens.textPrimary : ColorTokens.surface1)
                                .foregroundStyle(selected ? ColorTokens.surface0 : ColorTokens.textSecondary)
                                .clipShape(Circle())
                                .onTapGesture {
                                    if selected { selectedDays.remove(day) } else { selectedDays.insert(day) }
                                }
                        }
                    }
                }
                Section("Time range") {
                    DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle(existing == nil ? "New commitment" : "Edit commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") {
                        let days = CommitmentEntity.weekdaySymbols.filter { selectedDays.contains($0) }
                        if let existing {
                            existing.name = name
                            existing.icon = icon
                            existing.daysOfWeek = days.joined(separator: ",")
                            existing.startTime = startTime
                            existing.endTime = endTime
                        } else {
                            CommitmentEntity.create(
                                in: context,
                                name: name.isEmpty ? "Commitment" : name,
                                icon: icon,
                                days: days,
                                startTime: startTime,
                                endTime: endTime
                            )
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedDays.isEmpty)
                }
            }
        }
    }

    private static func defaultTime(_ hour: Int, _ minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? .now
    }
}

#Preview {
    NavigationStack { ScheduleSetupView(onFinished: {}) }
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).container.viewContext)
}
