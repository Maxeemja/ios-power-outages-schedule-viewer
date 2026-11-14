# Phase 3 Implementation Plan: YASNO Group Schedule

**Status:** Planning only. No Phase 3 provider implementation is authorized or started by this document revision.
**Approved product semantics:** display a selected YASNO group schedule, never an address-specific or individually verified property schedule. See [research](PHASE_3_DATA_SOURCE_RESEARCH.md) and [architecture](PHASE_3_ARCHITECTURE.md).

## Entry conditions and mandatory scope

The product decisions are settled: user-direct group selection, 6/12-hour freshness policy, and continued user-facing manual mode. Phase 3 does not depend on DTEK address-specific integration. Before implementation, use sanitized YASNO fixtures and verify provider response shape; do not assume historical schema remains current. Keep network calls in the main app, retain last-known-good data on all failures, and keep the widget offline-only. Group choices must come from actual provider data where supported; do not invent a complete catalog.

Every app/widget real-data view must state that the displayed schedule belongs to the selected group and that actual outages for an individual building or apartment may differ. Address-to-group mapping and address-based inference are out of scope. No address-specific accuracy claim is allowed. Manual schedule mode remains available alongside YASNO mode; switching modes must preserve each mode’s data and never cause automatic refresh to overwrite manual data.

### A. YASNO provider integration

**Objective:** Add an app-only `OutageDataSource` implementation and remote client for the verified planned-outages endpoint and selected group.

**Likely files/components:** new app service protocol/provider adapter and YASNO client under `OutageSchedule/App/...`; target membership/project file only if required. No widget network component.

**Dependencies:** sanitized fixture and verified request parameters/region/DSO selection policy grounded in provider metadata; direct group-selection model. Confirm group-key availability from the actual response before presenting choices.

**Acceptance criteria:** requests use the researched planned-outages route; region/operator values are not treated as permanent without validation; timeout, offline, non-2xx, redirect/protocol errors and wrong content type are surfaced as failures; no DTEK request or edge handling exists.

**Required tests:** injectable-session/client tests for successful response, timeout/offline, non-2xx including 429/5xx, wrong MIME type, empty body, and unexpected redirect/challenge content.

**Verification commands:** `rg -n "planned-outages|DTEK|URLSession" OutageSchedule`; run focused provider-client tests (exact `xcodebuild test` command determined from project scheme during implementation).

### B. Response parsing and domain mapping

**Objective:** Decode only fixture-supported YASNO response structures and map a selected group's supported planned schedule to existing schedule interval/status types.

**Likely files/components:** YASNO DTOs and a pure response validator/mapper in app data/service files; existing domain model only if a narrowly justified metadata field is needed.

**Dependencies:** A; current verified facts in [research](PHASE_3_DATA_SOURCE_RESEARCH.md); confirmed semantics for slot types/statuses; fresh sanitized fixtures.

**Acceptance criteria:** response must contain the requested group and valid supported day data; day dates/offsets and integer minute bounds are validated; unknown status/type, absent group/day, invalid or ambiguous intervals, and malformed payload fail closed; empty `WaitingForSchedule` is never turned into an all-available day; group identity remains explicit in mapped output.

**Required tests:** fixture decoding; malformed/changed schema; unknown fields/enums according to chosen decoder policy; missing group/day; waiting/empty day; valid and invalid slot ranges/order/overlap; timezone/offset and DST boundary cases supported by actual fixtures; exact mapping of observed status/type semantics.

**Verification commands:** focused mapper/DTO unit tests via `xcodebuild test -only-testing:<test-target>/<test-case>` (scheme/test target to be confirmed); inspect fixtures against `docs/PHASE_0_FINDINGS.md`.

### C. Direct group selection and identity

**Objective:** Let users directly select and recognize a YASNO group without representing it as address-specific schedule data.

**Likely files/components:** app selection UI/state; domain snapshot metadata in `OutageSchedule/Shared/Domain/OutageModels.swift`; related tests. No address resolver.

**Dependencies:** A/B and verified provider response keys. Group choices are derived from actual returned group keys when supported; coverage limitations must be surfaced rather than filled with guessed identifiers.

**Acceptance criteria:** selected identity stores provider plus exact group/subgroup string (including notation such as `19.1`); selection is validated against available provider data; group label is shown; no supposedly complete hardcoded catalog, address lookup, or address inference exists. Manual and YASNO modes remain independently selectable.

**Required tests:** identity round-trip preserving exact subgroup notation; rejected unavailable group; changing group refreshes/maps that group; switching modes retains each mode’s persisted data; legacy/manual snapshot remains intact.

**Verification commands:** focused model/selection tests; source/copy review for direct group selection and group-level disclaimer.

### D. Persistence and last-valid-snapshot behavior

**Objective:** Persist normalized group schedule, source identity, provider update timestamp, and client fetch time while preserving existing valid data on failure.

**Likely files/components:** `OutageSchedule/Shared/Domain/OutageModels.swift`, `OutageSchedule/Shared/Storage/ScheduleStore.swift`, app refresh coordinator, storage tests.

**Dependencies:** B and C; additive backward-compatible schema migration. Preserve current App Group atomic JSON mechanism.

**Acceptance criteria:** provider `updatedOn` remains distinct from local successful retrieval `fetchedAt`; source mode, provider and exact group identity are explicit; a valid snapshot is atomically saved; transport, invalid response, stale rejection, and save failure preserve last-known-good data; manual snapshots decode/migrate backward-compatibly; automatic refresh never overwrites manual data; widget reload follows successful write only.

**Required tests:** schema 1 manual snapshot backward-compatible migration/read; manual/YASNO mode switch and group change preserve each mode; metadata round-trip including `19.1`, `updatedOn`, and `fetchedAt`; atomic write; missing App Group/write failure; last-valid snapshot preserved for each failure class; no timeline reload after failed save.

**Verification commands:** focused `ScheduleStore` and coordinator tests; inspect serialized fixture/snapshot and verify `schemaVersion` migration behavior.

### E. UI integration and group-level labeling

**Objective:** Add selected-group refresh while retaining the existing manual user workflow and honest group-level meaning across app and widget.

**Likely files/components:** `OutageSchedule/App/ContentView.swift`; `OutageSchedule/Widget/WidgetViews.swift`; `OutageSchedule/Widget/OutageScheduleWidget.swift`; `OutageSchedule/Widget/OutageTimelineProvider.swift` only if data selection/freshness requires it; preserve `MockScheduleFactory`.

**Dependencies:** A-D; approved group selection; reviewed localized copy.

**Acceptance criteria:** app and widget identify selected group and visibly state that actual outages at an individual building/apartment may differ; manual and YASNO modes are clearly distinct and independently usable; switching mode or group causes no data loss or accidental overwrite; mock/demo state stays distinct; unavailable/stale states are understandable; widget consumes only persisted snapshot and makes no network request.

**Required tests:** view/model presentation tests where supported; widget snapshot tests or rendering checks for valid, stale, unavailable, and demo states; source review confirms no widget networking.

**Verification commands:** `rg -n "address|адрес|group|груп|будин|квартир" OutageSchedule/App OutageSchedule/Widget`; run focused UI/widget tests and manual simulator review after environment allows.

### F. Error handling and data freshness

**Objective:** Give users accurate refresh and freshness state based on provider `updatedOn`, not HTTP cache headers or local fetch time alone.

**Likely files/components:** YASNO client/mapper; app refresh coordinator and `ContentView`; snapshot metadata; widget freshness presentation.

**Dependencies:** A/B/D; approved product freshness policy; verified meaning/parseability of provider update time.

**Acceptance criteria:** age of `updatedOn` through 6 hours inclusive is CURRENT; over 6 through 12 hours inclusive is STALE; over 12 hours is STALE with stronger warning; missing/malformed/unusable timestamp is not current; future timestamp is invalid and rejected. Show provider update time separately from local `fetchedAt`; stale data never silently becomes fresh; refresh errors do not erase last-known-good data; waiting-for-schedule does not fabricate intervals; HTTP `Date`, `Cache-Control`, HTTP 200, and local fetch time never establish source freshness.

**Required tests:** timestamp parsing/timezone; exact 6-hour and 12-hour boundaries; >12-hour stronger warning; missing/malformed/future timestamp rejection; stale response; older payload after newer snapshot; waiting state; refresh failure with visible old snapshot.

**Verification commands:** focused freshness/coordinator tests; inspect UI copy against the researched 2026-11-11 observation where `updatedOn` lagged HTTP `Date` by about 20 hours.

### G. Unit tests and regression testing

**Objective:** Verify provider integration without ordinary tests depending on live YASNO or DTEK services and preserve existing manual/demo behavior.

**Likely files/components:** `OutageScheduleTests/` new provider, mapper, storage, coordinator, and presentation tests; existing `ScheduleDomainTests.swift`; test fixtures under the established test resource convention.

**Dependencies:** A-F and actual project target/resource configuration. Execute in order A (client) → B (mapping/validation) → C (direct selection) → D (schema and persistence) → E (app/widget UI) → F (freshness/error behavior) → G (regression suite) → H (build/final review); where implementation dependencies require, keep each phase gated on its listed prerequisites.

**Acceptance criteria:** tests use sanitized fixtures and an injected URL session; no live requests in the standard suite; all failure cases preserve last valid data; existing domain tests continue to pass; no DTEK implementation dependency is present.

**Required tests:** the tests specified in A-F plus regression coverage for `ScheduleCalculator`, manual snapshots, mock factory scenarios, and widget local reads.

**Verification commands:** `xcodebuild test -project OutageSchedule.xcodeproj -scheme OutageSchedule -destination 'platform=iOS Simulator,name=<available simulator>' CODE_SIGNING_ALLOWED=NO` (confirm actual available destination/scheme); focused `-only-testing` runs for changed test suites.

### H. Build verification and final review

**Objective:** Build app and widget, run unit tests, inspect final diff and verify product semantics/documentation/code agree.

**Likely files/components:** no additional files expected; project/target membership only if required to compile new app-only files.

**Dependencies:** A-G complete and available Xcode/simulator environment.

**Acceptance criteria:** app and widget targets build; relevant unit/regression tests pass; app and widget have no provider networking; group-level semantics and stale/error behavior agree; no unrelated settings/signing changes; full diff and `git diff --check` reviewed.

**Required tests:** full unit suite plus app/widget build; manual app and widget review when simulator services are available.

**Verification commands:** `xcodebuild -project OutageSchedule.xcodeproj -scheme OutageSchedule -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`; `xcodebuild test -project OutageSchedule.xcodeproj -scheme OutageSchedule -destination 'platform=iOS Simulator,name=<available simulator>' CODE_SIGNING_ALLOWED=NO`; `git diff --check`.

**Known environment issue:** the prior Ralph iteration reported a malformed SwiftUI `@State` macro-plugin response and simulator services unavailable; its build failed before successful verification. Treat this as unresolved environment/toolchain evidence, not an application code defect. Re-run and record exact output during implementation. Do not modify signing, provisioning, unrelated Xcode settings, or source code to conceal it.

## Out of scope

- DTEK address-specific integration, scraping, protection bypass, or browser automation.
- Address-to-group resolution or inferred group selection.
- Backend, authentication, push notifications, and multi-city support.
- Additional provider-health diagnostics are optional only if they do not expand product scope or store full addresses/raw payloads.

No Phase 4 tasks are defined here. Implementation remains paused pending explicit approval after this documentation revision.
