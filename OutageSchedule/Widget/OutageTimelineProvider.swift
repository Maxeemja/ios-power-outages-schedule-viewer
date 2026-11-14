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
        let staleAt = TimelinePolicy.manualExpiry(mode: store.activeMode, verifiedAt: store.loadManual()?.lastVerifiedAt)
        let dates = TimelinePolicy.dates(for: schedule, now: now, dayEnd: dayEnd, manualStaleAt: staleAt)

        let entryDates = ([now] + dates.filter { $0 > now }.sorted()).map {
            OutageWidgetEntry(date: $0, snapshot: currentSnapshot(now: $0))
        }
        let expiryRefresh = staleAt.flatMap { $0 > now ? $0.addingTimeInterval(60) : nil }
        let refreshDate = min(expiryRefresh ?? now.addingTimeInterval(30 * 60), dayEnd.addingTimeInterval(60))
        completion(Timeline(entries: entryDates, policy: .after(refreshDate)))
    }

    private func currentSnapshot(now: Date = .now) -> ScheduleSnapshot {
        let today = KyivTime.dayStart(containing: now)
        if store.activeMode == .yasno {
            guard let groupID = store.selectedYasnoGroup else {
                return MockScheduleFactory.unavailableSnapshot(now: now)
            }
            guard let saved = store.loadYasno(groupID: groupID), saved.scheduleDate == today,
                  saved.selectedSchedule != nil else {
                return yasnoUnavailable(groupID: groupID, now: now)
            }
            var displayed = saved
            if let groupID = saved.groupIdentity?.identifier,
               let waiting = store.loadYasnoWaiting(groupID: groupID), waiting.fetchedAt > saved.fetchedAt {
                displayed.providerWaitingUpdatedOn = waiting.updatedOn
                displayed.providerWaitingFetchedAt = waiting.fetchedAt
            }
            return displayed
        }
        let saved = store.load()
        guard saved != nil else { return MockScheduleFactory.unavailableSnapshot(now: now) }
        return TimelinePolicy.manualDisplaySnapshot(saved: saved, now: now)
    }

    private func yasnoUnavailable(groupID: String, now: Date) -> ScheduleSnapshot {
        var snapshot = MockScheduleFactory.unavailableSnapshot(now: now)
        snapshot.address = nil
        snapshot.sourceKind = .yasnoGroup
        snapshot.groupIdentity = ScheduleGroupIdentity(provider: .yasno, identifier: groupID)
        if let waiting = store.loadYasnoWaiting(groupID: groupID) {
            snapshot.fetchedAt = waiting.fetchedAt
            snapshot.sourceUpdatedOn = waiting.updatedOn
            snapshot.providerWaitingUpdatedOn = waiting.updatedOn
            snapshot.providerWaitingFetchedAt = waiting.fetchedAt
        }
        return snapshot
    }
}
