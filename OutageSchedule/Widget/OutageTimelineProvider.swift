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

        var nextTick = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 900) + 1) * 900)
        while nextTick < dayEnd {
            dates.insert(nextTick)
            nextTick = nextTick.addingTimeInterval(15 * 60)
        }

        let entryDates = ([now] + dates.filter { $0 > now }.sorted()).map {
            OutageWidgetEntry(date: $0, snapshot: snapshot)
        }
        let refreshDate = max(dayEnd.addingTimeInterval(60), now.addingTimeInterval(15 * 60))
        completion(Timeline(entries: entryDates, policy: .after(refreshDate)))
    }

    private func currentSnapshot(now: Date = .now) -> ScheduleSnapshot {
        let today = KyivTime.dayStart(containing: now)
        if let saved = store.load(), saved.scheduleDate == today {
            return saved
        }
        return MockScheduleFactory.snapshot(now: now)
    }
}
