# Phase 3A Implementation Plan for Phase 3B

**Status:** Planning only. Phase 3B has not been approved or started. No source files or project configuration were changed for this plan.

## Entry criteria

Before implementation, verify a provider-supported machine interface for DTEK Kyiv address lookup and schedule retrieval. Record current live responses, authentication/access terms, rate limits, update metadata, timezone, multi-feed behavior, and sanitized fixtures. The current official page is address-specific, but current direct HTTP requests return an Incapsula challenge. Do not implement a scraper or edge-control workaround. If there is no approved interface, stop and ask for a product decision on whether to defer real data or change to an explicitly labeled group schedule.

## Phase 3B steps

### Step 1 — Confirm scope and provider contract

- Confirm the approved endpoint and access method, supported geographic scope, and one real address test path.
- Capture sanitized fixtures for region/address suggestions, not-found response, normal schedule, no-schedule/waiting state, and multi-feed schedule if available.
- Record provider update timestamp semantics and official meaning of every interval/status.
- Decide whether this release handles one selected address or includes address search; confirm multi-feed selection UX.

**Acceptance:** Provider interface is supported/authorized, reachable without bypassing edge controls, and has enough observed fields to map a schedule without inferred semantics.

### Step 2 — Add DTO and client boundary

- Add the narrow `OutageDataSource` protocol and app-target provider implementation.
- Add an injectable `URLSession` client with timeout, status/content-type checks, and typed transport/protocol errors.
- Add Codable DTOs matching the approved real fixture only.
- Treat challenge HTML, unexpected redirects/content types, and unknown schema as errors.

**Acceptance:** Recorded fixtures decode; malformed JSON, wrong content type, HTTP errors, timeout, and changed required fields fail deterministically.

### Step 3 — Validate and map into the existing domain

- Implement pure validation for address identity, schedule identifiers, status semantics, provider date/timezone, interval boundaries/order/overlap, completeness, and freshness.
- Map supported meanings to existing `ScheduleStatus` and construct `AddressSchedule`/`ScheduleSnapshot`.
- Preserve provider-returned multiple schedules; do not invent a selection.
- Add a snapshot source-updated timestamp only if needed for honest freshness and only with an explicit schema version/migration decision.

**Acceptance:** Valid fixtures map exactly to expected internal models; invalid or ambiguous source semantics never become a confident “available” interval.

### Step 4 — Add app refresh orchestration and persistence

- Replace only the app's demo refresh action with a real refresh path when approved; retain the `MockScheduleFactory` and a deliberate demo/preview path.
- Keep last-known-good snapshot if network, validation, or storage fails.
- Save through `ScheduleStore`; reload WidgetKit timelines only after save succeeds.
- Show loading/success/stale/failure status in app without exposing raw payloads or addresses in logs.

**Acceptance:** Successful refresh persists a decodable snapshot in the existing App Group file and issues a timeline reload; every failed refresh leaves the previous snapshot intact.

### Step 5 — Widget behavior and manual Xcode verification

- Keep `OutageTimelineProvider` offline and use the existing snapshot age/date checks, adjusting only if the approved freshness semantics require it.
- Confirm the widget handles missing, invalid, wrong-day, stale, multi-schedule selection, and provider waiting states without showing mock data as live.
- Once code work is approved, perform Xcode build, unit tests, and manual simulator/widget verification. Phase 2 build/simulator behavior still has outstanding manual verification per project context.

**Acceptance:** Widget renders the saved last-known-good snapshot offline, handles stale/missing data honestly, and responds to a successful app-triggered reload when WidgetKit schedules it.

## Testing strategy

### Unit tests

- **DTO decoding:** normal schedule, multiple schedules, provider no-schedule state, missing optional fields, missing required fields, unknown enum/status, wrong JSON types, malformed JSON, and challenge HTML body.
- **HTTP client:** 2xx valid JSON, non-2xx status, timeout, no network, redirect/edge challenge, wrong MIME type, empty body, and response larger than any chosen defensive limit (only if a limit is defined from provider facts).
- **Validation:** requested-address mismatch; empty schedule list; unknown status; negative/out-of-range minute; start equal/after end; overlapping intervals; unsorted intervals; gaps where complete coverage is required; duplicate schedule IDs; impossible/ambiguous date; offset/timezone mismatch; DST boundary; stale update timestamp; future timestamp beyond allowed clock skew; tomorrow not published; multiple feed handling.
- **Mapping:** exact conversion of each provider semantic to internal `ScheduleStatus`; correct Kyiv-local boundaries; stable IDs; selected schedule retained only when explicitly chosen; no conversion of missing time to available.
- **Persistence:** round-trip internal snapshot; version rejection and migration if introduced; App Group unavailable; write failure; atomic-write behavior; failed save does not replace the previous good snapshot.
- **Refresh orchestration:** save then reload order; no reload after fetch/validation/save failure; old snapshot preserved on all failures; error state distinguishes stale/offline/invalid source/persistence failure.
- **Widget logic:** no network dependency; missing/wrong-day/stale snapshots; current-day data; provider waiting state; valid last-known-good data and schedule selection.

### Integration tests

- URLProtocol-backed or injected-session tests for the approved endpoint flow and representative sanitized fixtures; no live upstream calls in ordinary unit test runs.
- App-level flow from selected address to DTO decode, validation, mapping, App Group snapshot save, and timeline reload request (reload collaborator injectable for deterministic assertion).
- Widget target reads the same encoded snapshot from the configured App Group container and renders the expected selected schedule. Use an integration environment with the actual entitlement/container; unit test encoding alone does not prove signing configuration.
- Optional live smoke check only when authorized and stable, run manually/explicitly with a known test address; avoid relying on production network availability in CI.

### Failure acceptance criteria

- Network/provider failures do not erase or replace last-known-good data.
- An HTTP 200 HTML challenge is rejected as a provider protocol/access error.
- Stale schedule data is labeled stale and never represented as freshly fetched.
- Empty tomorrow/waiting data is not transformed into a fabricated all-available schedule.
- Invalid intervals and unknown status semantics are rejected before persistence.
- App Group write failure does not trigger a widget reload.
- Widget remains fully functional from local storage while offline and never performs upstream requests.

## Expected Phase 3B files

Exact filenames may follow existing Xcode group conventions after project inspection. Expected changes are limited to:

| File | Expected change |
|---|---|
| `OutageSchedule/Shared/Domain/OutageModels.swift` | Only if a justified source-updated/freshness field or stable provider schedule identity must be persisted; otherwise no change. Schema compatibility must be preserved or migrated. |
| `OutageSchedule/Shared/Storage/ScheduleStore.swift` | Likely no structural change; possibly expose typed persistence errors if refresh UI/tests need the distinction. Keep App Group path and atomic storage behavior. |
| `OutageSchedule/Shared/Services/OutageDataSource.swift` (new; path/name provisional) | Provider-independent fetch contract and narrow error type. Place according to current target membership setup. |
| `OutageSchedule/App/Data/OutageAPIClient.swift` (new; path/name provisional) | URLSession request/response boundary and HTTP validation. |
| `OutageSchedule/App/Data/DTEKOutageDataSource.swift` (new; conditional on source gate) | Provider endpoint flow and external DTOs, or split DTOs into a small same-folder file if useful. No WAF bypass. |
| `OutageSchedule/App/Data/ScheduleMapper.swift` (new; path/name provisional) | Pure validation and mapping from verified provider DTOs into existing internal models. |
| `OutageSchedule/App/ScheduleRefreshCoordinator.swift` (new; path/name provisional) | Fetch/validate/save/reload orchestration and last-known-good behavior. |
| `OutageSchedule/App/ContentView.swift` | Connect an approved refresh action and present refresh/freshness status; retain mock functionality. Address UI only if included in approved scope. |
| `OutageSchedule/Widget/OutageTimelineProvider.swift` | Change only if product freshness policy requires it; retain local-only reads and existing stale/missing safeguards. |
| `OutageScheduleTests/*` | Add DTO, client, mapper, store, coordinator, and widget behavior tests. |
| `OutageSchedule/Shared/Mock/MockScheduleFactory.swift` | Expected unchanged; retain demo/mock behavior. |

Project configuration should remain unchanged if the Xcode project automatically includes files in synchronized groups. If files require explicit target membership edits, explain that change and obtain Phase 3B approval before making it. Do not add packages or dependencies.

## Decisions still needed

1. Approval of a verified supported provider interface; this is a hard prerequisite, not an implementation detail.
2. Whether address search is in Phase 3B or the app receives a previously selected address.
3. Multi-feed address UX and persistence of selected schedule identity.
4. Provider stale threshold and whether to persist provider update time separately from client `fetchedAt`.
5. Whether refresh is manual-only initially or also uses an approved opportunistic app background task.
6. Whether UI should retain a visibly labeled mock/demo mode after live integration.

## Verification report expected after approval

After implementation is authorized, report exact changed files, fixture sources/date, build and unit-test commands/results, manual Xcode/Simulator verification still required, and any remaining provider reliability limits. Do not claim successful live integration based only on mocked URL responses or a successful HTTP status.
