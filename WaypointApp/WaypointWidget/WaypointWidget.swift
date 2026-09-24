import WidgetKit
import SwiftUI

struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        // The gallery preview gets stand-in content rather than an empty grey box — a real
        // store read there shows a blank widget to anyone browsing before they've used the app.
        let snapshot = context.isPreview ? DaySnapshot.placeholder : WidgetStore.todaySnapshot()
        completion(DayEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let snapshot = WidgetStore.todaySnapshot()
        let dates = snapshot.refreshDates()
        let entries = [DayEntry(date: .now, snapshot: snapshot)]
            + dates.map { DayEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WaypointWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaypointToday", provider: DayProvider()) { entry in
            WidgetTodayView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "waypoint://today"))
                // The accent, edge to edge, the same as the card this mirrors in the app.
                // `containerBackground` is what fills to the widget's real bounds — a colour
                // set on the content instead leaves the system's default margin showing.
                .containerBackground(for: .widget) {
                    ColorTokens.elevatedFill(
                        AccentSwatch.current.color, tier: .raised, isDark: false
                    )
                }
        }
        .configurationDisplayName("Today")
        .description("Your day at a glance. Tap a task to start a focus session.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct WaypointWidgetBundle: WidgetBundle {
    var body: some Widget {
        WaypointWidget()
    }
}
