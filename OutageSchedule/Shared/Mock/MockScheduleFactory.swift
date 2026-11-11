import Foundation

enum MockScheduleFactory {
    static func snapshot(now: Date = .now, selectedScheduleID: String = "line-a") -> ScheduleSnapshot {
        let dayStart = KyivTime.dayStart(containing: now)
        let schedules = [
            makeSchedule(id: "line-a", label: "Графік 1", day: dayStart, boundaries: [
                (0, 120, .available),
                (120, 240, .outage),
                (240, 360, .possible),
                (360, 720, .available),
                (720, 840, .outage),
                (840, 1080, .available),
                (1080, 1260, .outage),
                (1260, 1440, .available)
            ])
        ]

        return ScheduleSnapshot(
            schemaVersion: 1,
            address: SelectedAddress(city: "Київ", street: "вул. Демонстраційна", buildingNumber: "12"),
            schedules: schedules,
            selectedScheduleID: schedules.contains(where: { $0.id == selectedScheduleID }) ? selectedScheduleID : schedules[0].id,
            scheduleDate: dayStart,
            fetchedAt: now
        )
    }

    private static func makeSchedule(
        id: String,
        label: String,
        day: Date,
        boundaries: [(start: Int, end: Int, status: ScheduleStatus)]
    ) -> AddressSchedule {
        AddressSchedule(
            id: id,
            displayLabel: label,
            intervals: boundaries.enumerated().map { index, interval in
                ScheduleInterval(
                    id: "\(id)-\(index)",
                    start: KyivTime.date(on: day, minuteOfDay: interval.start),
                    end: KyivTime.date(on: day, minuteOfDay: interval.end),
                    status: interval.status
                )
            }
        )
    }
}
