import Foundation

struct SelectedAddress: Codable, Equatable {
    var city: String
    var street: String
    var buildingNumber: String

    var displayName: String {
        "\(street), \(buildingNumber)"
    }
}

enum ScheduleStatus: String, Codable, CaseIterable {
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
        case .available: "Є світло"
        case .outage: "Без світла"
        case .possible: "Можливо"
        case .unknown: "Немає даних"
        }
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
    var address: SelectedAddress
    var schedules: [AddressSchedule]
    var selectedScheduleID: String
    var scheduleDate: Date
    var fetchedAt: Date

    var selectedSchedule: AddressSchedule? {
        schedules.first { $0.id == selectedScheduleID } ?? schedules.first
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
        calendar().date(byAdding: .minute, value: minuteOfDay, to: dayStart(containing: day))!
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
