import Foundation
import WidgetKit

struct OutageWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleSnapshot
}

struct OutageTimelineProvider: TimelineProvider {
    private let store = ScheduleStore()

    func placeholder(in context: Context) -> OutageWidgetEntry {
        OutageWidgetEntry(date: .now, snapshot: MockScheduleFactory.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (OutageWidgetEntry) -> Void) {
        completion(OutageWidgetEntry(date: .now, snapshot: currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OutageWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = currentSnapshot(now: now)
        let schedule = snapshot.selectedSchedule
        let dayEnd = KyivTime.date(on: snapshot.scheduleDate, minuteOfDay: 1440)
        var dates: Set<Date> = []

        if let schedule {
            for interval in schedule.intervals {
                if interval.start > now { dates.insert(interval.start) }
                if interval.end > now && interval.end < dayEnd { dates.insert(interval.end) }
            }
        }

        // Refresh the static marker periodically; SwiftUI's timer text handles the countdown between entries.
        var nextTick = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 1800) + 1) * 1800)
        while nextTick < dayEnd {
            dates.insert(nextTick)
            nextTick = nextTick.addingTimeInterval(30 * 60)
        }

        let entryDates = ([now] + dates.filter { $0 > now }.sorted()).map {
            OutageWidgetEntry(date: $0, snapshot: snapshot)
        }
        let refreshDate = schedule == nil
            ? now.addingTimeInterval(30 * 60)
            : dayEnd.addingTimeInterval(60)
        completion(Timeline(entries: entryDates, policy: .after(refreshDate)))
    }

    private func currentSnapshot(now: Date = .now) -> ScheduleSnapshot {
        let today = KyivTime.dayStart(containing: now)
        guard let saved = store.load(), saved.scheduleDate == today else {
            return MockScheduleFactory.unavailableSnapshot(now: now)
        }
        let age = now.timeIntervalSince(saved.fetchedAt)
        guard age >= 0, age <= 24 * 60 * 60, saved.selectedSchedule != nil else {
            return MockScheduleFactory.unavailableSnapshot(now: now, basedOn: saved)
        }
        return saved
    }
}
