import SwiftUI
import Charts

struct ProgressAnalyticsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @FetchRequest private var recentTasks: FetchedResults<TaskEntity>

    init() {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        let start = cal.date(byAdding: .day, value: -60, to: end)!
        _recentTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(from: start, to: end))
    }

    private struct WeekBucket: Identifiable {
        let id: Int
        let label: String
        let completion: Double
    }

    private var weekBuckets: [WeekBucket] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<4).reversed().map { weeksAgo in
            let end = cal.date(byAdding: .day, value: -7 * weeksAgo, to: today)!
            let start = cal.date(byAdding: .day, value: -7, to: end)!
            let tasks = recentTasks.filter { $0.resolvedDate >= start && $0.resolvedDate < end }
            let fraction = tasks.isEmpty ? 0 : Double(tasks.filter(\.isDone).count) / Double(tasks.count)
            return WeekBucket(id: weeksAgo, label: "W\(4 - weeksAgo)", completion: fraction)
        }
    }

    private var avgCompletion: Double {
        let values = weekBuckets.map(\.completion)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var bestStreak: Int {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: recentTasks) { cal.startOfDay(for: $0.resolvedDate) }
        let fullyDoneDays = Set(byDay.compactMap { day, tasks -> Date? in
            guard !tasks.isEmpty, tasks.allSatisfy(\.isDone) else { return nil }
            return day
        })
        var best = 0
        var current = 0
        var cursor = cal.date(byAdding: .day, value: -59, to: cal.startOfDay(for: .now))!
        for _ in 0..<60 {
            if fullyDoneDays.contains(cursor) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return best
    }

    private var insight: String {
        let morning = recentTasks.filter { Calendar.current.component(.hour, from: $0.resolvedStartTime) < 12 }
        guard !morning.isEmpty else { return "Complete a few more tasks to unlock insights." }
        let rate = Double(morning.filter(\.isDone).count) / Double(morning.count)
        return "Mornings are your most productive time — \(Int(rate * 100))% completion before noon."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text("Progress")
                        .wpTypography(.screenTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    if !theme.isPro { ProBadge() }
                }
                .padding(.top, 8)
                Text("Last 4 weeks")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .padding(.top, -12)

                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(CurvedBackground(topHeight: 160))
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if theme.isPro {
            unlockedContent
        } else {
            unlockedContent
                .blur(radius: 6)
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(ColorTokens.textSecondary)
                        Text("Unlock trends, streaks, and time-of-day insights")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .multilineTextAlignment(.center)
                        ProBadge()
                    }
                    .padding(20)
                    .background(ColorTokens.surface1.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
        }
    }

    private var unlockedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Chart(weekBuckets) { bucket in
                BarMark(
                    x: .value("Week", bucket.label),
                    y: .value("Completion", bucket.completion)
                )
                .foregroundStyle(ColorTokens.success)
                .cornerRadius(6)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .frame(height: 140)

            HStack(spacing: 10) {
                statCard(value: "\(Int(avgCompletion * 100))%", label: "Avg completion")
                statCard(value: "\(bestStreak)", label: "Best streak")
            }

            Text(insight)
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textPrimary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wpCard(padding: 0)
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).wpTypography(.bigStat).foregroundStyle(ColorTokens.textPrimary)
            Text(label).wpTypography(.micro).foregroundStyle(ColorTokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .wpCard(padding: 0)
    }
}
