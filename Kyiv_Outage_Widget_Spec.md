# Kyiv Power Outage Widget — Product & Technical Specification

**Status:** Draft for MVP  
**Target:** Native iOS app + Home Screen widget  
**Language:** Swift / SwiftUI  
**Primary region:** Kyiv city, Ukraine  
**Timezone:** `Europe/Kyiv`

## 1. Product overview

Build a native iOS application that lets a user select their Kyiv electricity-distribution address, resolves that address to an outage group/queue, and displays the relevant planned outage schedule in an iOS Home Screen widget.

The widget should make it possible to answer at a glance:

- Which outage group is configured?
- Is electricity expected to be available now, or is an outage scheduled?
- When is the next planned outage or restoration?
- What does the rest of today look like?
- How fresh is the schedule data?

This is a schedule viewer, not a real-time electricity sensor. Never claim that electricity is physically present or absent based only on a planned schedule.

## 2. Important source research and constraints

### 2.1 Official operator source

The Ukrainian State Energy Supervision Inspectorate lists the official Kyiv city distribution operator page:

- DTEK Kyiv City Electrical Networks: https://www.dtek-kem.com.ua/ua/shutdowns

The official operator page is the authoritative place to verify address-to-group mapping and published schedules.

### 2.2 API availability

Do not assume that DTEK Kyiv City has a stable, documented public REST API.

A currently maintained community Python client documents the DTEK website's underlying WordPress AJAX flow. Its README describes:

1. Load the official shutdown page and discover the AJAX endpoint.
2. POST `method=getStreets` to retrieve street names.
3. POST `method=getHomeNum` with city, street, and an address/refresh timestamp.
4. Read house-to-group mapping plus `preset` (planned/template schedule) and `fact` (date-specific schedule) data.

Repository:
https://github.com/shed-crypto/dtek-blackout-client

The client supports `kem` for DTEK Kyiv City Networks and exposes address lookup and schedule methods. However, the same project documents WAF/anti-bot protection and, in some cases, browser-assisted session establishment. This is a material reliability risk for a direct iOS integration.

### 2.3 Other possible data source

A community API project describes a Kyiv outage API based on data from the official YASNO resource:

- Project: https://github.com/yevhenkizin/electricity_status_service_yasno
- API documentation URL advertised by its README: https://kyiv.electricstatus.click/docs

The documentation endpoint could not be independently fetched during preparation of this specification. Treat this as an **unverified third-party API candidate**, not a guaranteed production dependency. Before adopting it, verify:
- that the service is currently online;
- its actual endpoint paths and response schemas;
- address lookup support vs. group-only lookup;
- update cadence and timestamps;
- rate limits, CORS requirements (relevant only if using a web client), availability and terms;
- whether it is maintained and whether it has a service-level commitment.

### 2.4 Data-source decision

Implement a provider abstraction so the app does not depend on one source's schema.

**Recommended discovery order for the first technical spike:**

1. Inspect and test the YASNO-derived Kyiv API candidate. Prefer it only if it provides reliable address/group lookup and current schedule data.
2. In parallel, inspect the official DTEK Kyiv page and its AJAX protocol using the community client as a protocol reference.
3. If no stable direct source is suitable for an iOS client, consider a small server-side adapter that fetches/parses the upstream source, normalizes the response, and caches it. Do not build this backend before the spike proves it is necessary.

Do not silently scrape through anti-bot protections, embed browser automation in the iOS app, or make an undocumented endpoint look like an official API.

## 3. MVP scope

### Included

- Select a Kyiv address: city/locality, street, building number.
- Resolve the address to an outage group (for example `3.1`).
- Show the resolved address and group in the app.
- Display today's schedule in a Home Screen widget.
- Display current schedule state and the next scheduled transition.
- Show a compact timeline of today's outage intervals.
- Persist the selected address/group and last successful schedule locally.
- Show last-updated time and stale/offline state.
- Support at least Small and Medium widget families.
- Open the app when the user taps the widget.

### Explicitly out of scope for MVP

- Push notifications.
- Multiple saved addresses.
- Multiple widgets with different configurations.
- Live power-grid telemetry / proof of actual electricity availability.
- Apple Watch, Live Activities, Lock Screen widget.
- User accounts, cloud sync, custom backend unless required by the source.
- Historical analytics and outage statistics.

## 4. User flow

1. User opens the app.
2. User selects or searches a street in Kyiv.
3. User selects a building number.
4. App resolves the address to an outage group.
5. App shows the address, group, and a preview of the schedule.
6. User adds the widget to the Home Screen.
7. Widget reads the saved configuration and displays the latest cached schedule.
8. When fresh data becomes available, app/widget updates the shared cache and asks WidgetKit to reload its timeline.

If address lookup cannot resolve a group, show a clear error and allow the user to retry or manually select a group only if the provider supports this safely. Do not guess a group from a neighboring building.

## 5. Widget behavior and content

### Small widget

Show:
- outage group;
- current planned state: `Світло за графіком` / `Відключення за графіком` / `Немає актуального графіка`;
- next transition time;
- data freshness indicator.

### Medium widget

Show:
- group and abbreviated address;
- current planned state;
- today's outage intervals on a compact horizontal timeline;
- next transition;
- last successful update time.

Use neutral wording that makes it clear this is a **planned schedule**. For example, “За графіком: світло” rather than “Світло є”.

### Schedule states

The normalized domain model must preserve uncertainty. Suggested states:
- `available` — source explicitly indicates no planned outage in this interval;
- `outage` — source explicitly indicates planned outage;
- `possible` — source marks the interval as possible/uncertain;
- `unknown` — missing, unrecognized, or invalid source status.

Do not collapse `possible` or `unknown` into `available`.

### Stale data

- Show the timestamp of the last successful fetch.
- If data is older than a configurable freshness threshold (initial suggestion: 2 hours), mark it as stale.
- If a fetch fails, retain the last successful schedule but clearly mark it stale/offline.
- If no cached schedule exists, show a useful empty/error state.
- Never replace valid cached data with an empty response caused by a transient error.

## 6. Address and group configuration

For the initial Kyiv-only MVP, the address model should contain:

```swift
struct UserAddress: Codable, Equatable {
    let city: String
    let street: String
    let buildingNumber: String
    let apartmentNumber: String? // optional; only if the upstream source needs it
}

struct OutageGroup: Codable, Equatable {
    let id: String       // e.g. "3.1"
    let displayName: String
}
```

Persist the minimum necessary address data locally. Avoid collecting apartment number unless the upstream provider requires it. The widget can display a shortened address or only the group.

Address-to-group resolution must be performed against the selected operator/source. Kyiv city and Kyiv region are different distribution areas; do not accidentally use the Kyiv regional operator for a Kyiv city address.

## 7. Proposed architecture

Keep the app simple and modular. Avoid introducing a backend, database, or complex clean architecture without evidence that it is needed.

### Targets

- `OutageWidgetApp` — main iOS app.
- `OutageWidgetExtension` — WidgetKit extension.
- Shared source code or a small local Swift package for domain models, provider interfaces, and storage contracts.

### Suggested modules

- `Domain`
  - `UserAddress`
  - `OutageGroup`
  - `ScheduleDay`
  - `ScheduleInterval`
  - `ScheduleStatus`
  - `ScheduleSnapshot`
- `Data`
  - `OutageDataProvider` protocol
  - `KyivOutageAPIProvider` (only after the source spike)
  - `DTEKKyivProvider` (only if direct DTEK integration is selected)
  - `ScheduleRepository`
  - `SharedScheduleStore`
- `App`
  - address selection UI
  - address/group confirmation
  - schedule preview
  - refresh action
- `Widget`
  - `OutageWidget`
  - `OutageTimelineProvider`
  - Small and Medium SwiftUI views
  - widget configuration

### Data flow

1. App requests address suggestions / group mapping from the provider.
2. User confirms the resolved group.
3. App fetches the schedule.
4. Repository validates and normalizes upstream data.
5. Repository saves a `ScheduleSnapshot` to shared App Group storage.
6. App calls `WidgetCenter.shared.reloadTimelines(ofKind:)`.
7. Widget timeline provider reads the latest snapshot from the shared store and renders it.
8. Widget timeline entries are scheduled around known transitions where useful, subject to WidgetKit's system-controlled refresh budget.

### Shared storage

Use an App Group shared container for data read by both the app and widget extension.

For MVP, a versioned JSON file is sufficient:
- atomic writes;
- `Codable` models;
- schema version;
- `fetchedAt`;
- `scheduleDate`;
- source identifier;
- normalized schedule;
- selected address/group.

`UserDefaults(suiteName:)` may store small settings, but a JSON file in the App Group container is preferable for the schedule snapshot.

## 8. WidgetKit and refresh strategy

WidgetKit does not provide a continuously running widget process. iOS controls timeline refresh and may delay requested reloads.

Requirements:
- Do not promise minute-by-minute updates.
- Do not poll continuously from the widget.
- Fetch when the app launches or returns to foreground, and when the user explicitly refreshes.
- The widget should render immediately from cached data.
- Use timeline entries for known schedule transitions, but respect system refresh policy.
- Optionally request background app refresh later, but do not make MVP correctness depend on it.
- A widget tap should open the app, where a fresh fetch can occur.

All schedule calculations must use `Europe/Kyiv`, not the device's current timezone. This matters when the user is physically outside Ukraine.

## 9. API/provider contract

Do not spread upstream JSON models through the UI. Normalize all sources behind a protocol.

Illustrative contract:

```swift
protocol OutageDataProvider {
    func searchStreets(city: String, query: String) async throws -> [Street]
    func fetchBuildings(city: String, street: String) async throws -> [Building]
    func resolveAddress(_ address: UserAddress) async throws -> OutageGroup
    func fetchSchedule(
        group: OutageGroup,
        date: Date
    ) async throws -> ScheduleDay
}
```

The actual contract may be simplified after the source investigation. If the selected API accepts a group ID only, address resolution may be a separate provider operation.

Normalized schedule model:

```swift
struct ScheduleSnapshot: Codable {
    let schemaVersion: Int
    let source: String
    let fetchedAt: Date
    let scheduleDate: Date
    let address: UserAddress?
    let group: OutageGroup
    let intervals: [ScheduleInterval]
}

struct ScheduleInterval: Codable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let status: ScheduleStatus
}

enum ScheduleStatus: String, Codable {
    case available
    case outage
    case possible
    case unknown
}
```

Treat these as conceptual examples, not a mandate to copy exact types before inspecting the real API schema.

## 10. Reliability, validation, and security

- Validate all API responses before saving.
- Handle HTTP errors, timeouts, rate limits, malformed JSON, and unknown enum values.
- Add bounded retries only for transient failures.
- Keep the last-known-good snapshot.
- Record source and fetch timestamp.
- Avoid logging full residential addresses.
- Do not request location permission; the user selects an address manually.
- Do not store secrets in the app bundle.
- Respect upstream terms and rate limits.
- Do not bypass WAF/anti-bot controls in the iOS app.
- If a proxy backend is required, keep it stateless where possible and cache normalized public schedule data.

## 11. Testing strategy

### Unit tests
- Address normalization and lookup mapping.
- Parsing and normalization of source responses.
- Mapping source statuses to domain statuses.
- Current status and next-transition calculation.
- Kyiv timezone and midnight/date-boundary handling.
- Stale-data classification.
- Unknown source status handling.

### Integration tests
- Provider contract against saved fixtures.
- API timeout / 429 / 5xx / malformed response.
- Cache read/write and schema version handling.
- App Group storage access from app and widget targets.

### Manual tests
- First launch with no cached data.
- Successful address resolution.
- Unknown/unavailable address.
- Network disabled after a successful fetch.
- Old cached data.
- Schedule changes during the day.
- Widget reload after app refresh.
- Device timezone set outside Kyiv.
- Small and Medium widget layouts.
- App and widget after device restart.

## 12. Implementation plan for the coding agent

Work in small phases. Do not implement the whole product in one pass.

### Phase 0 — Source/API spike (no app implementation yet)
1. Inspect the YASNO-derived API documentation and test actual endpoints.
2. Determine whether it supports address lookup, group lookup, and daily schedule retrieval.
3. Inspect the official DTEK Kyiv City page and compare its current behavior.
4. Capture sanitized sample responses as fixtures.
5. Document freshness, availability, rate limits, and failure modes.
6. Recommend one provider and explain why.
7. Stop and ask for approval before building the integration.

**Acceptance:** A documented provider decision backed by successful real requests and sample payloads. If no suitable source exists, propose a minimal backend adapter before proceeding.

### Phase 1 — App skeleton and widget preview
1. Create the Xcode project and Widget Extension.
2. Configure App Groups.
3. Implement domain models and mock data.
4. Build Small and Medium widget previews.
5. Run a simulator build.

**Acceptance:** Mock schedule renders correctly in both widget sizes.

### Phase 2 — Address configuration
1. Implement address search and selection using the approved provider.
2. Resolve the address to a group.
3. Confirm and persist the selection.
4. Show the group and schedule preview in the app.

**Acceptance:** A real selected address resolves to the correct group, with no guessed mapping.

### Phase 3 — Schedule fetching and cache
1. Implement provider adapter.
2. Normalize source payloads.
3. Persist a versioned snapshot in App Group storage.
4. Add stale/offline behavior.
5. Add tests and fixtures.

**Acceptance:** The app displays live provider data and preserves last-known-good data after a fetch failure.

### Phase 4 — Widget integration
1. Read the shared snapshot in the timeline provider.
2. Render current state, next transition, and daily intervals.
3. Configure timeline refresh policy.
4. Reload widget timelines after successful app refresh.
5. Validate timezone behavior.

**Acceptance:** Widget displays cached schedule without network access and updates after app refresh.

### Phase 5 — Polish
1. Accessibility and Dynamic Type.
2. Light/Dark appearance.
3. Loading, empty, stale, and error states.
4. Layout tests and device testing.
5. Release build.

## 13. Instructions to the AI coding agent

- Read this specification and the repository's `AGENTS.md` before making changes.
- Start with Phase 0. Do not jump to UI implementation before validating the data source.
- Do not invent API endpoints, payload fields, or sample data.
- Cite URLs, files, and exact response fields used to justify the provider decision.
- Distinguish verified facts from assumptions.
- Do not add a backend unless the source spike demonstrates it is necessary.
- Do not introduce dependencies without explaining their value.
- Ask questions when a product decision is genuinely ambiguous.
- Before each phase, propose a concise plan and acceptance criteria.
- Implement one phase at a time; run builds and tests after each phase.
- Do not modify unrelated files.
- At the end of each phase, report changed files, verification commands/results, unresolved risks, and the next recommended step.
- Stop for approval at the end of Phase 0.

## 14. References

- State Energy Supervision Inspectorate — list of official distribution operator outage pages:
  https://sies.gov.ua/zvernennya-gromadyan/najbilsh-zapituvana-informaciya/grafiki-vidklyuchen-elektropostachannya-operatoriv-sistemi-rozpodilu
- DTEK Kyiv City official outage page:
  https://www.dtek-kem.com.ua/ua/shutdowns
- Community DTEK client / reverse-engineered AJAX protocol:
  https://github.com/shed-crypto/dtek-blackout-client
- Community YASNO-derived Kyiv API candidate:
  https://github.com/yevhenkizin/electricity_status_service_yasno
- Advertised API docs (not independently verified during research):
  https://kyiv.electricstatus.click/docs
- WidgetKit documentation:
  https://developer.apple.com/documentation/widgetkit
- App Groups documentation:
  https://developer.apple.com/documentation/xcode/configuring-app-groups
