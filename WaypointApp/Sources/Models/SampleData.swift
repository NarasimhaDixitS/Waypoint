import Foundation
import CoreData

enum SampleData {
    static func seed(into context: NSManagedObjectContext) {
        let now = Date.now
        let cal = Calendar.current

        let goal = GoalEntity.create(
            in: context,
            name: "Exam prep",
            targetDate: cal.date(byAdding: .day, value: 48, to: now)!,
            planningMode: .manual
        )
        goal.createdAt = cal.date(byAdding: .day, value: -11, to: now)!

        _ = CommitmentEntity.create(
            in: context,
            name: "Gym",
            icon: "gym",
            days: ["Mon", "Wed", "Fri"],
            startTime: time(7, 30),
            endTime: time(8, 30)
        )
        _ = CommitmentEntity.create(
            in: context,
            name: "Team meeting",
            icon: "meeting",
            days: CommitmentEntity.weekdaySymbols.filter { $0 != "Sat" && $0 != "Sun" },
            startTime: time(11, 30),
            endTime: time(13, 0)
        )

        TaskEntity.create(
            in: context,
            title: "Morning run, 30 min",
            date: now,
            startTime: now.addingTimeInterval(-3 * 3600),
            durationMinutes: 30,
            priority: .medium,
            goal: nil
        ).also { $0.isDone = true; $0.completedAt = now.addingTimeInterval(-2.5 * 3600) }

        TaskEntity.create(
            in: context,
            title: "Deep work: thesis ch. 3",
            date: now,
            startTime: now.addingTimeInterval(-15 * 60),
            durationMinutes: 120,
            priority: .high,
            goal: goal,
            notes: nil
        )

        TaskEntity.create(
            in: context,
            title: "Review lecture notes",
            date: now,
            startTime: now.addingTimeInterval(3 * 3600),
            durationMinutes: 60,
            priority: .medium,
            goal: goal
        )

        TaskEntity.create(
            in: context,
            title: "Meal prep for tomorrow",
            date: now,
            startTime: now.addingTimeInterval(7 * 3600),
            durationMinutes: 30,
            priority: .low,
            goal: nil
        )

        for offset in 1...36 {
            let day = cal.date(byAdding: .day, value: -offset, to: now)!
            let didComplete = Double.random(in: 0...1) < 0.78
            let task = TaskEntity.create(
                in: context,
                title: "Practice set \(offset)",
                date: day,
                startTime: cal.date(byAdding: .hour, value: 9, to: cal.startOfDay(for: day))!,
                durationMinutes: 45,
                priority: Priority.allCases.randomElement()!,
                goal: goal
            )
            task.isDone = didComplete
            task.completedAt = didComplete ? day : nil
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Seed failed: \(error)")
        }
    }

    private static func time(_ hour: Int, _ minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }
}

private extension TaskEntity {
    @discardableResult
    func also(_ body: (TaskEntity) -> Void) -> TaskEntity {
        body(self)
        return self
    }
}
