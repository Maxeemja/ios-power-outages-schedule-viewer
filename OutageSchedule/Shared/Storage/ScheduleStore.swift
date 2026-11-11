import Foundation

struct ScheduleStore {
    static let appGroupIdentifier = "group.com.example.OutageSchedule"
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var snapshotURL: URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent("schedule-snapshot.json", isDirectory: false)
    }

    func load() -> ScheduleSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return Self.decode(data)
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
