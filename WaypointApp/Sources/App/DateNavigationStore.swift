import Foundation

/// The day currently being browsed on the Today screen — shared so that other screens
/// (e.g. tapping a day in Week) can jump Today to a specific date.
@MainActor
final class DateNavigationStore: ObservableObject {
    @Published var selectedDate: Date = .now
}
