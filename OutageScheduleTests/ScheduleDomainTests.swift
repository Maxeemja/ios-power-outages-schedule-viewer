import XCTest

final class ScheduleDomainTests: XCTestCase {
    func testSnapshotRoundTripsThroughSharedStoreCodableHelpers() throws {
        let original = MockScheduleFactory.snapshot(now: fixedDate())
        let data = try XCTUnwrap(ScheduleStore.encode(original))
        let restored = try XCTUnwrap(ScheduleStore.decode(data))
        XCTAssertEqual(restored, original)
    }

    func testCalculatorUsesHalfOpenIntervalBoundary() throws {
        let schedule = try XCTUnwrap(MockScheduleFactory.snapshot(now: fixedDate()).schedules.first)
        let boundary = schedule.intervals[0].end
        XCTAssertEqual(ScheduleCalculator.currentInterval(in: schedule, at: boundary)?.status, .outage)
    }

    func testNextTransitionReturnsTimeAndUpcomingStatus() throws {
        let schedule = try XCTUnwrap(MockScheduleFactory.snapshot(now: fixedDate()).schedules.first)
        let now = schedule.intervals[0].start.addingTimeInterval(30 * 60)
        let transition = try XCTUnwrap(ScheduleCalculator.nextTransition(in: schedule, at: now))
        XCTAssertEqual(transition.date, schedule.intervals[0].end)
        XCTAssertEqual(transition.status, .outage)
    }

    func testMockSupportsMoreThanOneScheduleForAnAddress() {
        let snapshot = MockScheduleFactory.snapshot(now: fixedDate())
        XCTAssertEqual(snapshot.schedules.count, 2)
        XCTAssertEqual(snapshot.selectedSchedule?.id, "line-a")
    }

    func testCountdownRoundsUpToTheNextMinute() {
        let now = fixedDate()
        XCTAssertEqual(ScheduleCalculator.countdown(until: now.addingTimeInterval(61), from: now), "2 хв")
    }

    func testMockIntervalsAreBuiltOnKyivCalendarDay() {
        let now = fixedDate()
        let snapshot = MockScheduleFactory.snapshot(now: now)
        XCTAssertEqual(snapshot.scheduleDate, KyivTime.dayStart(containing: now))
        XCTAssertEqual(KyivTime.calendar().component(.hour, from: snapshot.schedules[0].intervals[0].start), 0)
    }

    func testManualScheduleExpiresAfterTwoHours() {
        var snapshot = MockScheduleFactory.snapshot(now: fixedDate())
        snapshot.sourceKind = .userEntered
        snapshot.lastVerifiedAt = fixedDate()

        XCTAssertTrue(snapshot.isFreshManualSchedule(at: fixedDate().addingTimeInterval(2 * 60 * 60)))
        XCTAssertFalse(snapshot.isFreshManualSchedule(at: fixedDate().addingTimeInterval(2 * 60 * 60 + 1)))
        XCTAssertFalse(snapshot.isFreshManualSchedule(at: fixedDate().addingTimeInterval(-1)))
    }

    func testSnapshotWithoutManualMetadataRemainsDecodable() throws {
        var snapshot = MockScheduleFactory.snapshot(now: fixedDate())
        snapshot.sourceKind = .userEntered
        snapshot.lastVerifiedAt = fixedDate()
        let encoded = try XCTUnwrap(ScheduleStore.encode(snapshot))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "sourceKind")
        object.removeValue(forKey: "lastVerifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let restored = try XCTUnwrap(ScheduleStore.decode(legacyData))
        XCTAssertNil(restored.sourceKind)
        XCTAssertNil(restored.lastVerifiedAt)
    }

    func testKyivScheduleDayEndsAtNextLocalMidnightAcrossDST() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-28T22:00:00Z"))
        let dayStart = KyivTime.dayStart(containing: date)
        let dayEnd = KyivTime.date(on: dayStart, minuteOfDay: 1440)

        XCTAssertEqual(KyivTime.calendar().component(.day, from: dayEnd), 30)
        XCTAssertEqual(dayEnd.timeIntervalSince(dayStart), 23 * 60 * 60)
    }

    private func fixedDate() -> Date {
        ISO8601DateFormatter().date(from: "2026-11-09T10:00:00Z")!
    }
}
