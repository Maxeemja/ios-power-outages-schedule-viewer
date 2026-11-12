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
        let verifiedAt = store.load()?.lastVerifiedAt
        let staleAt = verifiedAt?.addingTimeInterval(ScheduleSnapshot.manualScheduleFreshness)

        if let schedule {
            for interval in schedule.intervals {
                if interval.start > now && (staleAt == nil || interval.start < staleAt!) { dates.insert(interval.start) }
                if interval.end > now && interval.end < dayEnd && (staleAt == nil || interval.end < staleAt!) { dates.insert(interval.end) }
            }
        }

        if let staleAt, staleAt > now {
            dates.insert(staleAt.addingTimeInterval(1))
        }

        let entryDates = ([now] + dates.filter { $0 > now }.sorted()).map {
            OutageWidgetEntry(date: $0, snapshot: currentSnapshot(now: $0))
        }
        let expiryRefresh = staleAt.flatMap { $0 > now ? $0.addingTimeInterval(60) : nil }
        let refreshDate = min(expiryRefresh ?? now.addingTimeInterval(30 * 60), dayEnd.addingTimeInterval(60))
        completion(Timeline(entries: entryDates, policy: .after(refreshDate)))
    }

    private func currentSnapshot(now: Date = .now) -> ScheduleSnapshot {
        let today = KyivTime.dayStart(containing: now)
        guard let saved = store.load(),
              saved.scheduleDate == today,
              saved.sourceKind == .userEntered else {
            return MockScheduleFactory.unavailableSnapshot(now: now)
        }
        guard saved.isFreshManualSchedule(at: now), saved.selectedSchedule != nil else {
            return MockScheduleFactory.unavailableSnapshot(now: now, basedOn: saved)
        }
        return saved
    }
}
