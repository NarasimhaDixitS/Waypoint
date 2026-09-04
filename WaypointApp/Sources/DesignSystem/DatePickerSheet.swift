import SwiftUI

/// Shared by every screen that shows a date as a plain tappable value rather than an inline
/// `DatePicker` — the task editor and goal creation both do. Keeps a draft copy so backing out
/// with Cancel leaves the bound value untouched, the same contract `TimePickerSheet` has.
struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    @Binding var date: Date
    /// Floor for selectable dates — goal target dates can't be in the past, while an existing
    /// task's date can be moved anywhere. `nil` means no restriction.
    var notBefore: Date?

    @State private var draftDate: Date

    init(date: Binding<Date>, notBefore: Date? = nil) {
        _date = date
        self.notBefore = notBefore
        _draftDate = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let notBefore {
                    DatePicker("", selection: $draftDate, in: notBefore..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                } else {
                    DatePicker("", selection: $draftDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }
                Spacer()
            }
            .padding(20)
            .background(ColorTokens.surface0.ignoresSafeArea())
            .navigationTitle("Set date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        date = draftDate
                        dismiss()
                    }
                    .tint(theme.accentSwatch.color)
                }
            }
        }
    }
}
