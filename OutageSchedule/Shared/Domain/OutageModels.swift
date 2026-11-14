import Foundation

struct SelectedAddress: Codable, Equatable {
    var city: String
    var street: String
    var buildingNumber: String

    var displayName: String {
        "\(street), \(buildingNumber)"
    }
}

enum ScheduleStatus: String, Codable, CaseIterable, Hashable {
    case available
    case outage
    case possible
    case unknown

    var title: String {
        switch self {
        case .available: "Світло за графіком"
        case .outage: "Відключення за графіком"
        case .possible: "Можливе відключення"
        case .unknown: "Немає актуального графіка"
        }
    }

    var shortTitle: String {
        switch self {
        case .available: "За графіком: світло"
        case .outage: "За графіком: відкл."
        case .possible: "Можл. за графіком"
        case .unknown: "Немає даних"
        }
    }
}

enum ScheduleSourceKind: String, Codable {
    case userEntered
    case yasnoGroup
}

enum ScheduleProvider: String, Codable {
    case yasno
}

struct ScheduleGroupIdentity: Codable, Equatable, Hashable {
    var provider: ScheduleProvider
    /// Exact provider key, including subgroup notation (for example `19.1`).
    var identifier: String
}

enum ProviderFreshness: Equatable {
    case current
    case stale
    case staleWithStrongWarning
    case unavailable
    case invalidFutureTimestamp

    static func evaluate(updatedOn: Date?, now: Date) -> ProviderFreshness {
        guard let updatedOn else { return .unavailable }
        let age = now.timeIntervalSince(updatedOn)
        guard age >= 0 else { return .invalidFutureTimestamp }
        if age <= 6 * 60 * 60 { return .current }
        if age <= 12 * 60 * 60 { return .stale }
        return .staleWithStrongWarning
    }
}

struct ScheduleInterval: Codable, Equatable, Identifiable {
    var id: String
    var start: Date
    var end: Date
    var status: ScheduleStatus
}

struct AddressSchedule: Codable, Equatable, Identifiable {
    var id: String
    var displayLabel: String
    var intervals: [ScheduleInterval]
}

struct ScheduleSnapshot: Codable, Equatable {
    var schemaVersion: Int
    // Optional so group snapshots do not need a fabricated address; legacy snapshots still decode.
    var address: SelectedAddress?
    var schedules: [AddressSchedule]
    var selectedScheduleID: String
    var scheduleDate: Date
    var fetchedAt: Date
    // Optional so snapshots written before manual schedules remain decodable.
    var sourceKind: ScheduleSourceKind? = nil
    var lastVerifiedAt: Date? = nil
    // Additive metadata: absent in schema 1 manual snapshots.
    var groupIdentity: ScheduleGroupIdentity? = nil
    var sourceUpdatedOn: Date? = nil
    // Timeline overlays from the separate publication-state file; not part of the last valid schedule.
    var providerWaitingUpdatedOn: Date? = nil
    var providerWaitingFetchedAt: Date? = nil

    var selectedSchedule: AddressSchedule? {
        schedules.first { $0.id == selectedScheduleID } ?? schedules.first
    }

    static let manualScheduleFreshness: TimeInterval = 2 * 60 * 60

    func isFreshManualSchedule(at date: Date) -> Bool {
        guard sourceKind == .userEntered, let lastVerifiedAt else { return false }
        let age = date.timeIntervalSince(lastVerifiedAt)
        return age >= 0 && age <= Self.manualScheduleFreshness
    }

    var isYasnoGroupSchedule: Bool {
        sourceKind == .yasnoGroup && groupIdentity?.provider == .yasno
    }

    func providerFreshness(at date: Date) -> ProviderFreshness {
        guard isYasnoGroupSchedule else { return .unavailable }
        return ProviderFreshness.evaluate(updatedOn: sourceUpdatedOn, now: date)
    }
}

enum KyivTime {
    static let timeZone = TimeZone(identifier: "Europe/Kyiv")!

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func dayStart(containing date: Date) -> Date {
        calendar().startOfDay(for: date)
    }

    static func date(on day: Date, minuteOfDay: Int) -> Date {
        let calendar = calendar()
        let start = dayStart(containing: day)
        if minuteOfDay <= 0 { return start }
        if minuteOfDay >= 1440 {
            return calendar.date(byAdding: .day, value: 1, to: start)!
        }
        return calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: start,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? start
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

enum ScheduleCalculator {
    static func currentInterval(in schedule: AddressSchedule, at date: Date) -> ScheduleInterval? {
        schedule.intervals.first { $0.start <= date && date < $0.end }
    }

    static func nextTransition(in schedule: AddressSchedule, at date: Date) -> (date: Date, status: ScheduleStatus)? {
        if let current = currentInterval(in: schedule, at: date) {
            guard let next = schedule.intervals.first(where: { $0.start == current.end }) else {
                return nil
            }
            return (current.end, next.status)
        }

        guard let next = schedule.intervals.first(where: { $0.start > date }) else {
            return nil
        }
        return (next.start, next.status)
    }

    static func countdown(until date: Date, from now: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 {
            return "\(remainder) хв"
        }
        return remainder == 0 ? "\(hours) год" : "\(hours) год \(remainder) хв"
    }
}

/// Deterministic policies shared by WidgetKit timeline construction and regression tests.
enum TimelinePolicy {
    static func manualExpiry(mode: DisplayScheduleMode, verifiedAt: Date?) -> Date? {
        guard mode == .manual, let verifiedAt else { return nil }
        return verifiedAt.addingTimeInterval(ScheduleSnapshot.manualScheduleFreshness)
    }

    static func dates(
        for schedule: AddressSchedule?,
        now: Date,
        dayEnd: Date,
        manualStaleAt: Date?
    ) -> [Date] {
        var dates: Set<Date> = []
        if let schedule {
            for interval in schedule.intervals {
                if interval.start > now && (manualStaleAt.map { interval.start <= $0 } ?? true) {
                    dates.insert(interval.start)
                }
                if interval.end > now && interval.end < dayEnd
                    && (manualStaleAt.map { interval.end <= $0 } ?? true) {
                    dates.insert(interval.end)
                }
            }
        }
        if let manualStaleAt, manualStaleAt > now {
            dates.insert(manualStaleAt.addingTimeInterval(1))
        }
        return dates.filter { $0 > now }.sorted()
    }

    static func manualDisplaySnapshot(saved: ScheduleSnapshot?, now: Date) -> ScheduleSnapshot {
        guard let saved,
              saved.scheduleDate == KyivTime.dayStart(containing: now),
              saved.sourceKind == .userEntered,
              saved.isFreshManualSchedule(at: now),
              saved.selectedSchedule != nil else {
            return MockScheduleFactory.unavailableSnapshot(now: now, basedOn: saved)
        }
        return saved
    }
}
