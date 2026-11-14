import Foundation

enum DisplayScheduleMode: String, Hashable {
    case manual
    case yasno
}

struct ScheduleStore {
    static let appGroupIdentifier = "group.com.example.OutageSchedule"
    private let fileManager: FileManager
    private let defaults: UserDefaults?
    private let containerURLProvider: () -> URL?

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults? = UserDefaults(suiteName: ScheduleStore.appGroupIdentifier),
        containerURLProvider: (() -> URL?)? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.containerURLProvider = containerURLProvider ?? {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
        }
    }

    var activeMode: DisplayScheduleMode {
        get { defaults?.string(forKey: "active-schedule-mode").flatMap(DisplayScheduleMode.init(rawValue:)) ?? .manual }
        nonmutating set { defaults?.set(newValue.rawValue, forKey: "active-schedule-mode") }
    }

    var selectedYasnoGroup: String? {
        get { defaults?.string(forKey: "selected-yasno-group") }
        nonmutating set {
            if let newValue { defaults?.set(newValue, forKey: "selected-yasno-group") }
            else { defaults?.removeObject(forKey: "selected-yasno-group") }
        }
    }

    private var snapshotURL: URL? {
        containerURLProvider()?
            .appendingPathComponent("schedule-snapshot.json", isDirectory: false)
    }

    func load() -> ScheduleSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return Self.decode(data)
    }

    /// Loads and decodes an existing manual snapshot independently of the active display mode.
    func loadManual() -> ScheduleSnapshot? {
        guard let data = snapshotData else { return nil }
        return Self.decode(data).flatMap { $0.sourceKind == .userEntered || $0.sourceKind == nil ? $0 : nil }
    }

    @discardableResult
    func save(_ snapshot: ScheduleSnapshot) -> Bool {
        guard let url = snapshotURL,
              let data = Self.encode(snapshot) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Stores the automatic schedule in a separate file so refreshes cannot replace manual data.
    @discardableResult
    func saveYasno(_ snapshot: ScheduleSnapshot) -> Bool {
        guard snapshot.isYasnoGroupSchedule,
              snapshot.providerFreshness(at: snapshot.fetchedAt) == .current,
              let identifier = snapshot.groupIdentity?.identifier,
              let container = containerURLProvider() else { return false }
        do {
            let destination = container.appendingPathComponent(yasnoFilename(identifier))
            if let currentData = try? Data(contentsOf: destination),
               let current = Self.decode(currentData),
               let currentUpdatedOn = current.sourceUpdatedOn,
               let newUpdatedOn = snapshot.sourceUpdatedOn,
               currentUpdatedOn > newUpdatedOn {
                return false
            }
            var persisted = snapshot
            persisted.providerWaitingUpdatedOn = nil
            persisted.providerWaitingFetchedAt = nil
            guard let cleanData = Self.encode(persisted) else { return false }
            try cleanData.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func saveYasnoWaiting(groupID: String, updatedOn: Date, fetchedAt: Date) -> Bool {
        guard let container = containerURLProvider() else { return false }
        let state = YasnoWaitingState(groupID: groupID, updatedOn: updatedOn, fetchedAt: fetchedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return false }
        do {
            try data.write(to: container.appendingPathComponent(yasnoWaitingFilename(groupID)), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func loadYasnoWaiting(groupID: String) -> YasnoWaitingState? {
        guard let container = containerURLProvider(),
              let data = try? Data(contentsOf: container.appendingPathComponent(yasnoWaitingFilename(groupID))) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(YasnoWaitingState.self, from: data)
    }

    func loadYasno(groupID: String? = nil) -> ScheduleSnapshot? {
        guard let identifier = groupID ?? selectedYasnoGroup else { return nil }
        guard let container = containerURLProvider(),
              let data = try? Data(contentsOf: container.appendingPathComponent(yasnoFilename(identifier))),
              let snapshot = Self.decode(data), snapshot.isYasnoGroupSchedule else { return nil }
        return snapshot
    }

    private func yasnoFilename(_ identifier: String) -> String {
        let encoded = Data(identifier.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "yasno-\(encoded).json"
    }

    private func yasnoWaitingFilename(_ identifier: String) -> String {
        "waiting-" + String(yasnoFilename(identifier).dropFirst("yasno-".count))
    }

    private var snapshotData: Data? {
        guard let url = snapshotURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func encode(_ snapshot: ScheduleSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> ScheduleSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(ScheduleSnapshot.self, from: data),
              snapshot.schemaVersion == 1 else {
            return nil
        }
        return snapshot
    }
}

struct YasnoWaitingState: Codable, Equatable {
    var groupID: String
    var updatedOn: Date
    var fetchedAt: Date
}
