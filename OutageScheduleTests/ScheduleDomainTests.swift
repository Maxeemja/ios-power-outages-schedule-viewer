import Foundation
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

    func testManualExpirationAddsFallbackEntryAndDoesNotClaimLaterTransitions() throws {
        var snapshot = MockScheduleFactory.snapshot(now: fixedDate())
        snapshot.sourceKind = .userEntered
        snapshot.lastVerifiedAt = fixedDate()
        let schedule = try XCTUnwrap(snapshot.selectedSchedule)
        let now = fixedDate().addingTimeInterval(30 * 60)
        let staleAt = fixedDate().addingTimeInterval(ScheduleSnapshot.manualScheduleFreshness)
        let dates = TimelinePolicy.dates(
            for: schedule, now: now, dayEnd: KyivTime.date(on: snapshot.scheduleDate, minuteOfDay: 1440),
            manualStaleAt: staleAt
        )

        XCTAssertEqual(dates.last, staleAt.addingTimeInterval(1))
        XCTAssertFalse(dates.contains { $0 > staleAt.addingTimeInterval(1) })
        let expired = TimelinePolicy.manualDisplaySnapshot(saved: snapshot, now: staleAt.addingTimeInterval(1))
        XCTAssertNil(expired.selectedSchedule)
    }

    func testManualScheduleWithoutValidVerificationFallsBackToUnavailable() {
        var snapshot = MockScheduleFactory.snapshot(now: fixedDate())
        snapshot.sourceKind = .userEntered
        snapshot.lastVerifiedAt = nil

        let displayed = TimelinePolicy.manualDisplaySnapshot(saved: snapshot, now: fixedDate())

        XCTAssertNil(displayed.selectedSchedule)
        XCTAssertTrue(displayed.schedules.isEmpty)
    }

    func testManualTransitionAtFreshnessCutoffRemainsInTimeline() {
        let now = fixedDate()
        let cutoff = now.addingTimeInterval(ScheduleSnapshot.manualScheduleFreshness)
        let schedule = AddressSchedule(id: "manual", displayLabel: "Manual", intervals: [
            ScheduleInterval(id: "one", start: now, end: cutoff, status: .available),
            ScheduleInterval(id: "two", start: cutoff, end: cutoff.addingTimeInterval(3600), status: .outage)
        ])

        let dates = TimelinePolicy.dates(
            for: schedule, now: now, dayEnd: cutoff.addingTimeInterval(3600), manualStaleAt: cutoff
        )

        XCTAssertEqual(dates.first, cutoff)
        XCTAssertEqual(dates.last, cutoff.addingTimeInterval(1))
    }

    func testYasnoTransitionsAreNotSuppressedByManualExpiration() throws {
        let snapshot = try XCTUnwrap({ () throws -> ScheduleSnapshot? in
            guard case let .schedule(value) = try YasnoScheduleMapper.map(
                data: try yasnoFixture(), groupID: "19.1",
                fetchedAt: ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!
            ) else { return nil }
            return value
        }())
        let schedule = try XCTUnwrap(snapshot.selectedSchedule)
        let now = schedule.intervals[0].start.addingTimeInterval(30 * 60)
        let oldManualVerification = now.addingTimeInterval(-3 * 60 * 60)
        let yasnoModeExpiry = TimelinePolicy.manualExpiry(mode: .yasno, verifiedAt: oldManualVerification)
        let dates = TimelinePolicy.dates(
            for: schedule, now: now,
            dayEnd: KyivTime.date(on: snapshot.scheduleDate, minuteOfDay: 1440),
            manualStaleAt: yasnoModeExpiry
        )

        XCTAssertEqual(dates.first, schedule.intervals[0].end)
        XCTAssertNil(yasnoModeExpiry)
        XCTAssertTrue(dates.contains { $0 > now.addingTimeInterval(60) })
    }

    func testTimelineFallbackWhenNoSourceIsValidHasNoScheduleTransitions() {
        let now = fixedDate()
        let unavailable = TimelinePolicy.manualDisplaySnapshot(saved: nil, now: now)
        let dates = TimelinePolicy.dates(
            for: unavailable.selectedSchedule, now: now,
            dayEnd: KyivTime.date(on: unavailable.scheduleDate, minuteOfDay: 1440),
            manualStaleAt: nil
        )

        XCTAssertNil(unavailable.selectedSchedule)
        XCTAssertTrue(dates.isEmpty)
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

    func testYasnoFixturePreservesSubgroupAndMapsObservedSlots() throws {
        let data = try yasnoFixture()
        let now = ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!
        let result = try YasnoScheduleMapper.map(data: data, groupID: "19.1", fetchedAt: now)
        guard case let .schedule(snapshot) = result else { return XCTFail("Expected schedule") }
        XCTAssertEqual(snapshot.groupIdentity?.identifier, "19.1")
        XCTAssertEqual(snapshot.sourceKind, .yasnoGroup)
        XCTAssertEqual(snapshot.schedules.first?.intervals.map(\.status), [.outage, .available, .outage, .available, .outage])
        XCTAssertEqual(snapshot.sourceUpdatedOn, now)
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testYasnoGroupChoicesComeFromFixtureKeys() throws {
        XCTAssertEqual(try YasnoScheduleMapper.availableGroupIDs(data: yasnoFixture()), ["19.1"])
    }

    func testYasnoMissingGroupFailsClosed() throws {
        XCTAssertThrowsError(try YasnoScheduleMapper.map(
            data: yasnoFixture(), groupID: "19", fetchedAt: ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!
        )) { XCTAssertEqual($0 as? YasnoScheduleError, .missingGroup) }
    }

    func testYasnoWaitingDayRemainsWaitingAndDoesNotCreateSchedule() throws {
        let data = try changedFixture { group in
            var today = try XCTUnwrap(group["today"] as? [String: Any])
            today["status"] = "WaitingForSchedule"
            today["slots"] = []
            group["today"] = today
        }
        let result = try YasnoScheduleMapper.map(data: data, groupID: "19.1", fetchedAt: ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!)
        guard case .waiting(groupID: "19.1", _) = result else { return XCTFail("Expected explicit waiting state") }
    }

    func testYasnoUnknownStatusAndIncompleteSlotsFailClosed() throws {
        let badStatus = try changedFixture { group in
            var today = try XCTUnwrap(group["today"] as? [String: Any])
            today["status"] = "Unrecognized"
            group["today"] = today
        }
        let now = ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!
        XCTAssertThrowsError(try YasnoScheduleMapper.map(data: badStatus, groupID: "19.1", fetchedAt: now))

        let incomplete = try changedFixture { group in
            var today = try XCTUnwrap(group["today"] as? [String: Any])
            today["slots"] = [["start": 0, "end": 1439, "type": "NotPlanned"]]
            group["today"] = today
        }
        XCTAssertThrowsError(try YasnoScheduleMapper.map(data: incomplete, groupID: "19.1", fetchedAt: now))
    }

    func testLegacyManualSnapshotAndYasnoGroupPersistSeparately() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: "ScheduleStoreTests-\(UUID().uuidString)")!
        let store = ScheduleStore(defaults: defaults, containerURLProvider: { directory })

        var manual = MockScheduleFactory.snapshot(now: fixedDate())
        manual.sourceKind = .userEntered
        let legacyData = try XCTUnwrap(ScheduleStore.encode(manual))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        object.removeValue(forKey: "groupIdentity")
        object.removeValue(forKey: "sourceUpdatedOn")
        try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent("schedule-snapshot.json"))
        XCTAssertEqual(store.loadManual()?.sourceKind, .userEntered)

        let now = ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!
        guard case let .schedule(yasno) = try YasnoScheduleMapper.map(data: yasnoFixture(), groupID: "19.1", fetchedAt: now) else {
            return XCTFail("Expected mapped YASNO schedule")
        }
        store.selectedYasnoGroup = "19.1"
        XCTAssertTrue(store.saveYasno(yasno))
        store.activeMode = .yasno
        XCTAssertEqual(store.loadManual()?.sourceKind, .userEntered)
        XCTAssertEqual(store.loadYasno()?.groupIdentity?.identifier, "19.1")
        store.activeMode = .manual
        XCTAssertEqual(store.loadYasno()?.groupIdentity?.identifier, "19.1")
    }

    func testSimulatorAppGroupPersistsScheduleBetweenStoreInstances() throws {
        let writer = ScheduleStore()
        let reader = ScheduleStore()
        let groupID = "phase31-\(UUID().uuidString)"
        let container = try XCTUnwrap(FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ScheduleStore.appGroupIdentifier
        ))
        let encodedID = Data(groupID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let persistedFile = container.appendingPathComponent("yasno-\(encodedID).json")
        defer { try? FileManager.default.removeItem(at: persistedFile) }

        let fetchedAt = ISO8601DateFormatter().date(from: "2026-11-14T20:52:18Z")!
        guard case var .schedule(snapshot) = try YasnoScheduleMapper.map(
            data: liveScheduleFixture(), groupID: "19.1", fetchedAt: fetchedAt
        ) else {
            return XCTFail("Expected schedule from captured live response")
        }
        snapshot.groupIdentity = ScheduleGroupIdentity(provider: .yasno, identifier: groupID)

        XCTAssertTrue(writer.saveYasno(snapshot))
        XCTAssertEqual(reader.loadYasno(groupID: groupID), snapshot)
    }

    func testOlderYasnoPayloadCannotReplaceLastKnownGoodSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScheduleStore(
            defaults: UserDefaults(suiteName: "ScheduleStoreTests-\(UUID().uuidString)"),
            containerURLProvider: { directory }
        )
        let now = ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!
        guard case let .schedule(current) = try YasnoScheduleMapper.map(data: yasnoFixture(), groupID: "19.1", fetchedAt: now) else {
            return XCTFail("Expected mapped YASNO schedule")
        }
        XCTAssertTrue(store.saveYasno(current))

        var older = current
        older.sourceUpdatedOn = current.sourceUpdatedOn?.addingTimeInterval(-60)
        older.fetchedAt = now.addingTimeInterval(1)
        XCTAssertFalse(store.saveYasno(older))
        XCTAssertEqual(store.loadYasno(groupID: "19.1"), current)
    }

    func testProviderFreshnessBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ProviderFreshness.evaluate(updatedOn: now.addingTimeInterval(-6 * 3600), now: now), .current)
        XCTAssertEqual(ProviderFreshness.evaluate(updatedOn: now.addingTimeInterval(-6 * 3600 - 1), now: now), .stale)
        XCTAssertEqual(ProviderFreshness.evaluate(updatedOn: now.addingTimeInterval(-12 * 3600), now: now), .stale)
        XCTAssertEqual(ProviderFreshness.evaluate(updatedOn: now.addingTimeInterval(-12 * 3600 - 1), now: now), .staleWithStrongWarning)
        XCTAssertEqual(ProviderFreshness.evaluate(updatedOn: nil, now: now), .unavailable)
        XCTAssertEqual(ProviderFreshness.evaluate(updatedOn: now.addingTimeInterval(1), now: now), .invalidFutureTimestamp)
    }

    func testYasnoClientUsesVerifiedMetadataAndFixtureResponse() async throws {
        let session = stubSession { request in
            if request.url?.path.hasSuffix("/addresses/v2/regions") == true {
                return (200, "application/json", Data("[{\"id\":25,\"value\":\"Київ\",\"dsos\":[{\"id\":902,\"name\":\"ТОВ ДТЕК КИЇВСЬКІ ЕЛЕКТРОМЕРЕЖІ\"}]}]".utf8))
            }
            return (200, "application/json", try Data(contentsOf: Bundle(for: Self.self).url(forResource: "yasno-planned-outages", withExtension: "json")!))
        }
        let source = YasnoScheduleSource(session: session, regionsEndpoint: URL(string: "https://app.yasno.ua/test/addresses/v2/regions")!)
        let now = ISO8601DateFormatter().date(from: "2026-11-07T11:45:01Z")!
        guard case let .schedule(snapshot) = try await source.fetchSchedule(groupID: "19.1", fetchedAt: now) else {
            return XCTFail("Expected mapped fixture schedule")
        }
        XCTAssertEqual(snapshot.groupIdentity?.identifier, "19.1")
    }

    func testYasnoLiveCaptureResolvesKyivAndMapsCurrentWireFormat() async throws {
        let liveRegions = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "yasno-live-regions", withExtension: "json"
        )))
        let liveSchedule = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "yasno-live-planned-outages", withExtension: "json"
        )))
        var requests: [URL] = []
        let session = stubSession { request in
            let url = try XCTUnwrap(request.url)
            requests.append(url)
            if url.path.hasSuffix("/addresses/v2/regions") {
                return (200, "application/json", liveRegions)
            }
            return (200, "application/json", liveSchedule)
        }
        let source = YasnoScheduleSource(
            session: session,
            regionsEndpoint: URL(string: "https://app.yasno.ua/test/addresses/v2/regions")!
        )
        let fetchedAt = ISO8601DateFormatter().date(from: "2026-11-14T20:52:18Z")!

        let groupIDs = try await source.fetchAvailableGroupIDs()
        XCTAssertEqual(groupIDs, ["19.1"])
        guard case let .schedule(snapshot) = try await source.fetchSchedule(groupID: "19.1", fetchedAt: fetchedAt) else {
            return XCTFail("Expected schedule from captured live YASNO response")
        }

        XCTAssertEqual(snapshot.groupIdentity?.identifier, "19.1")
        XCTAssertEqual(snapshot.scheduleDate, KyivTime.dayStart(containing: fetchedAt))
        XCTAssertEqual(snapshot.sourceUpdatedOn, ISO8601DateFormatter().date(from: "2026-11-14T18:30:02Z"))
        XCTAssertEqual(snapshot.selectedSchedule?.intervals.map(\.status), [.available, .outage, .available, .outage, .available])
        XCTAssertTrue(requests.contains { $0.path == "/test/addresses/v2/regions" })
        XCTAssertTrue(requests.contains { $0.path == "/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages" })
    }

    func testYasnoClientRejectsHTTPAndWrongContentType() async throws {
        let source = YasnoScheduleSource(
            session: stubSession { _ in (429, "application/json", Data()) },
            regionsEndpoint: URL(string: "https://app.yasno.ua/test/regions")!
        )
        do {
            _ = try await source.fetchAvailableGroupIDs()
            XCTFail("Expected HTTP error")
        } catch {
            XCTAssertEqual(error as? YasnoScheduleError, .httpStatus(429))
        }

        let htmlSource = YasnoScheduleSource(
            session: stubSession { _ in (200, "text/html", Data("challenge".utf8)) },
            regionsEndpoint: URL(string: "https://app.yasno.ua/test/regions")!
        )
        do {
            _ = try await htmlSource.fetchAvailableGroupIDs()
            XCTFail("Expected content type error")
        } catch {
            XCTAssertEqual(error as? YasnoScheduleError, .invalidContentType)
        }
    }

    func testYasnoClientRejectsServerErrorsEmptyBodiesRedirectsAndTransportFailures() async throws {
        for statusCode in [500, 503] {
            let source = YasnoScheduleSource(
                session: stubSession { _ in (statusCode, "application/json", Data("{}".utf8)) },
                regionsEndpoint: URL(string: "https://app.yasno.ua/test/regions")!
            )
            do {
                _ = try await source.fetchAvailableGroupIDs()
                XCTFail("Expected HTTP error for status \(statusCode)")
            } catch {
                XCTAssertEqual(error as? YasnoScheduleError, .httpStatus(statusCode))
            }
        }

        let emptySource = YasnoScheduleSource(
            session: stubSession { _ in (200, "application/json", Data()) },
            regionsEndpoint: URL(string: "https://app.yasno.ua/test/regions")!
        )
        do {
            _ = try await emptySource.fetchAvailableGroupIDs()
            XCTFail("Expected malformed empty response")
        } catch {
            XCTAssertEqual(error as? YasnoScheduleError, .malformedPayload)
        }

        let redirectSource = YasnoScheduleSource(
            session: stubSession { _ in (200, "application/json", Data("[]".utf8)) },
            regionsEndpoint: URL(string: "https://app.yasno.ua/test/regions")!
        )
        YasnoStubURLProtocol.responseURLOverride = URL(string: "https://challenge.example/regions")
        do {
            _ = try await redirectSource.fetchAvailableGroupIDs()
            XCTFail("Expected redirected response to be rejected")
        } catch {
            XCTAssertEqual(error as? YasnoScheduleError, .invalidResponse)
        }
        YasnoStubURLProtocol.responseURLOverride = nil

        let transportFailureSource = YasnoScheduleSource(
            session: stubSession { _ in throw URLError(.notConnectedToInternet) },
            regionsEndpoint: URL(string: "https://app.yasno.ua/test/regions")!
        )
        do {
            _ = try await transportFailureSource.fetchAvailableGroupIDs()
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    private func yasnoFixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "yasno-planned-outages", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func liveScheduleFixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "yasno-live-planned-outages", withExtension: "json"
        ))
        return try Data(contentsOf: url)
    }

    private func changedFixture(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: yasnoFixture()) as? [String: Any])
        var group = try XCTUnwrap(root["19.1"] as? [String: Any])
        try change(&group)
        root["19.1"] = group
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func stubSession(_ handler: @escaping (URLRequest) throws -> (Int, String, Data)) -> URLSession {
        YasnoStubURLProtocol.handler = handler
        YasnoStubURLProtocol.responseURLOverride = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [YasnoStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func fixedDate() -> Date {
        ISO8601DateFormatter().date(from: "2026-11-09T10:00:00Z")!
    }
}

private final class YasnoStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String, Data))?
    static var responseURLOverride: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler, let url = request.url else { throw URLError(.badURL) }
            let (status, contentType, data) = try handler(request)
            let response = HTTPURLResponse(url: Self.responseURLOverride ?? url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
