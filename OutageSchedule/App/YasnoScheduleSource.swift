import Foundation

protocol OutageDataSource {
    func fetchSchedule(groupID: String, fetchedAt: Date) async throws -> YasnoFetchResult
}

enum YasnoFetchResult {
    case schedule(ScheduleSnapshot)
    case waiting(groupID: String, updatedOn: Date)
}

enum YasnoScheduleError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case invalidContentType
    case malformedPayload
    case missingGroup
    case missingDay
    case waitingForSchedule
    case invalidUpdatedOn
    case stale(ProviderFreshness)
    case invalidSchedule
}

struct YasnoScheduleSource: OutageDataSource {
    private let session: URLSession
    private let regionsEndpoint: URL

    init(session: URLSession = .shared, regionsEndpoint: URL = URL(string: "https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/regions")!) {
        self.session = session
        self.regionsEndpoint = regionsEndpoint
    }

    func fetchAvailableGroupIDs() async throws -> [String] {
        let endpoint = try await plannedOutagesEndpoint()
        let (data, _) = try await fetchData(from: endpoint)
        return try YasnoScheduleMapper.availableGroupIDs(data: data)
    }

    func fetchSchedule(groupID: String, fetchedAt: Date = .now) async throws -> YasnoFetchResult {
        guard !groupID.isEmpty else {
            throw YasnoScheduleError.invalidRequest
        }
        // Resolve current region and DSO IDs from YASNO metadata; researched numeric IDs are not treated as permanent.
        let endpoint = try await plannedOutagesEndpoint()
        let (data, _) = try await fetchData(from: endpoint)
        return try YasnoScheduleMapper.map(data: data, groupID: groupID, fetchedAt: fetchedAt)
    }

    private func plannedOutagesEndpoint() async throws -> URL {
        let (data, _) = try await fetchData(from: regionsEndpoint)
        guard let regions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw YasnoScheduleError.malformedPayload
        }
        let matches = regions.compactMap { region -> (Int, Int)? in
            guard region["value"] as? String == "Київ",
                  let regionID = region["id"] as? Int,
                  let dsos = region["dsos"] as? [[String: Any]] else { return nil }
            let kyivDSOs = dsos.compactMap { dso -> Int? in
                guard let name = dso["name"] as? String,
                      name.localizedCaseInsensitiveContains("ДТЕК"),
                      name.localizedCaseInsensitiveContains("КИЇВСЬКІ ЕЛЕКТРОМЕРЕЖІ") else { return nil }
                return dso["id"] as? Int
            }
            guard kyivDSOs.count == 1, let dsoID = kyivDSOs.first else { return nil }
            return (regionID, dsoID)
        }
        guard matches.count == 1, let (regionID, dsoID) = matches.first else {
            throw YasnoScheduleError.invalidResponse
        }
        return URL(string: "https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/\(regionID)/dsos/\(dsoID)/planned-outages")!
    }

    private func fetchData(from url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw YasnoScheduleError.invalidResponse }
        guard response.url == url else { throw YasnoScheduleError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw YasnoScheduleError.httpStatus(response.statusCode) }
        guard response.mimeType?.lowercased() == "application/json" else { throw YasnoScheduleError.invalidContentType }
        return (data, response)
    }
}

enum YasnoScheduleMapper {
    private struct Slot: Decodable {
        let start: Int
        let end: Int
        let type: String
    }
    private struct Day: Decodable {
        let slots: [Slot]
        let date: String
        let status: String
    }
    private struct Group: Decodable {
        let today: Day
        let tomorrow: Day
        let updatedOn: String
    }

    static func availableGroupIDs(data: Data) throws -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YasnoScheduleError.malformedPayload
        }
        return object.keys.filter { key in
            guard !key.isEmpty, let value = object[key], JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let group = try? JSONDecoder().decode(Group.self, from: data),
                  parseISO8601(group.updatedOn) != nil else { return false }
            return true
        }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func map(data: Data, groupID: String, fetchedAt: Date) throws -> YasnoFetchResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YasnoScheduleError.malformedPayload
        }
        guard root[groupID] != nil else { throw YasnoScheduleError.missingGroup }
        guard let groupData = try? JSONSerialization.data(withJSONObject: root[groupID]!),
              let group = try? JSONDecoder().decode(Group.self, from: groupData) else {
            throw YasnoScheduleError.malformedPayload
        }
        guard let updatedOn = parseISO8601(group.updatedOn) else { throw YasnoScheduleError.invalidUpdatedOn }
        let freshness = ProviderFreshness.evaluate(updatedOn: updatedOn, now: fetchedAt)
        guard freshness != .invalidFutureTimestamp else { throw YasnoScheduleError.invalidUpdatedOn }
        guard freshness == .current else { throw YasnoScheduleError.stale(freshness) }
        let expectedToday = KyivTime.dayStart(containing: fetchedAt)
        let expectedTomorrow = KyivTime.calendar().date(byAdding: .day, value: 1, to: expectedToday)!
        let dayDate = try validate(group.today, expectedDate: expectedToday)
        _ = try validate(group.tomorrow, expectedDate: expectedTomorrow)
        if group.today.status == "WaitingForSchedule" {
            return .waiting(groupID: groupID, updatedOn: updatedOn)
        }

        var intervals: [ScheduleInterval] = []
        var previousEnd = 0
        let dayStart = KyivTime.dayStart(containing: dayDate)
        for (index, slot) in group.today.slots.enumerated() {
            guard slot.start == previousEnd, slot.end > slot.start, slot.end <= 1440 else {
                throw YasnoScheduleError.invalidSchedule
            }
            let status: ScheduleStatus
            switch slot.type {
            case "Definite": status = .outage
            case "NotPlanned": status = .available
            default: throw YasnoScheduleError.invalidSchedule
            }
            let start = KyivTime.date(on: dayStart, minuteOfDay: slot.start)
            let end = KyivTime.date(on: dayStart, minuteOfDay: slot.end)
            guard end > start else { throw YasnoScheduleError.invalidSchedule }
            intervals.append(ScheduleInterval(id: "yasno-\(groupID)-\(index)", start: start, end: end, status: status))
            previousEnd = slot.end
        }
        guard previousEnd == 1440 else { throw YasnoScheduleError.invalidSchedule }

        let schedule = AddressSchedule(id: groupID, displayLabel: "Група \(groupID)", intervals: intervals)
        let snapshot = ScheduleSnapshot(
            schemaVersion: 1,
            address: nil,
            schedules: [schedule], selectedScheduleID: groupID,
            scheduleDate: dayStart, fetchedAt: fetchedAt,
            sourceKind: .yasnoGroup,
            groupIdentity: ScheduleGroupIdentity(provider: .yasno, identifier: groupID),
            sourceUpdatedOn: updatedOn
        )
        return .schedule(snapshot)
    }

    private static func validate(_ day: Day, expectedDate: Date) throws -> Date {
        guard let date = parseISO8601(day.date), KyivTime.calendar().isDate(date, inSameDayAs: expectedDate) else {
            throw YasnoScheduleError.missingDay
        }
        switch day.status {
        case "WaitingForSchedule":
            guard day.slots.isEmpty else { throw YasnoScheduleError.invalidSchedule }
        case "ScheduleApplies":
            guard !day.slots.isEmpty else { throw YasnoScheduleError.missingDay }
            var previousEnd = 0
            let dayStart = KyivTime.dayStart(containing: date)
            for slot in day.slots {
                guard slot.start == previousEnd, slot.end > slot.start, slot.end <= 1440,
                      slot.type == "Definite" || slot.type == "NotPlanned",
                      KyivTime.date(on: dayStart, minuteOfDay: slot.end) > KyivTime.date(on: dayStart, minuteOfDay: slot.start) else {
                    throw YasnoScheduleError.invalidSchedule
                }
                previousEnd = slot.end
            }
            guard previousEnd == 1440 else { throw YasnoScheduleError.invalidSchedule }
        default:
            throw YasnoScheduleError.invalidSchedule
        }
        return date
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
