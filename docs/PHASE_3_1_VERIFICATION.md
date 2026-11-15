# Phase 3.1 Verification

**Run date:** 2026-11-14  
**Overall status:** **PARTIAL** — live compatibility, App Group exchange, and most rendered-state checks passed. A direct countdown-state visual check could not be completed because WidgetKit retained its cached timeline during the synthetic-state attempt.

## Execution checklist

- [x] Inspect project instructions, architecture, documentation, targets, schemes, environment, and working tree.
- [x] Check live YASNO endpoints and preserve sanitized response fixtures.
- [x] Build the app and WidgetKit extension on an iOS 27.2 simulator.
- [x] Run the full deterministic test suite, including live-capture decoding and simulator App Group persistence.
- [x] Run the extension and inspect actual Small and Medium Home Screen widgets.
- [x] Inspect live schedule in light and dark appearances and unavailable/stale states in light appearance.
- [ ] Render and inspect an upcoming-transition countdown state; current live schedule had no remaining transition, and the synthetic snapshot did not displace WidgetKit's cached timeline.
- [x] Fix objectively visible text truncation and clean-install storage messaging issues.
- [x] Restore pre-existing simulator schedule data and complete regression verification.

## Environment

- Xcode 27.2 (build 27B52); iOS Simulator 27.2.
- iPhone 15 Pro simulator, UDID `39BD58BC-C407-4097-B8A6-7E1FC0BD599A`, used for actual widget extension execution. iPhone 18 Pro was also available and used for app-state inspection.
- Schemes: `OutageSchedule` and the added shared `OutageScheduleWidget` extension run scheme. Targets: app, widget extension, tests.
- `Simulator.app` is absent from the Xcode installation, but Xcode's `xcdebug` scheme runner launched the extension on simulator SpringBoard and rendered actual widgets. No screenshot here is a SwiftUI preview.
- The initial working tree contained a modified Xcode user-interface state file. Xcode use changed it further; it was preserved without restoration to avoid discarding the user's pre-existing change.
- iPhone 15 Pro had an existing manual snapshot. It was backed up before validation and restored byte-for-byte (`cmp` passed). Test-created YASNO data was removed. Shared preferences were returned to manual mode with no selected YASNO group.

## Live YASNO compatibility — **PASS**

The existing service performs metadata lookup, then fetches planned outages. Both exact app endpoints were called directly over HTTPS with `curl`; no authentication or access-control bypass was used:

```text
GET https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/regions
GET https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages
```

Both are plain GETs with no query parameters, body, or custom request headers; the app uses a 20-second timeout. The planned-outages response was JSON.

- Regions returned HTTP 200 and identified Kyiv as region `25`, DSO `902`, matching the service's Kyiv/DSO selection rule.
- Planned outages returned HTTP 200, 41,102 bytes, `Cache-Control: max-age=300, public`, and 60 group keys. Observed records contained `today`, `tomorrow`, `ScheduleApplies`, and slot types `Definite` or `NotPlanned`.
- Group `19.1` included `updatedOn` `2026-11-14T18:30:02Z`; captured-time fixture tests decoded its date, subgroup key, timestamp, and five expected interval statuses.
- The app validates HTTP status, final response URL, JSON MIME type, and timeout. Existing tests cover HTTP/content-type/redirect/empty-payload/transport failures. Required DTO fields and incomplete or unexpected schedule data fail closed. Live responses did not exercise null values, waiting state, or server failures; these remain fixture/test concerns.
- An exploratory wrong route returned HTTP 404 and was not used.
- The feed is outage-group data. This run establishes no address-specific schedule.

Sanitized captures: [regions](../OutageScheduleTests/Fixtures/yasno-live-regions.json) and [planned outages](../OutageScheduleTests/Fixtures/yasno-live-planned-outages.json). The latter contains only public group `19.1`; unrelated groups, headers, and cookies were not retained.

## App Group cross-process validation — **PASS**

- App and extension entitlements both declare `group.com.example.OutageSchedule`; the store uses that identifier for shared defaults and its container.
- Snapshot writes use atomic replacement. Widget reads through the shared store and does not make network requests.
- A simulator XCTest wrote a schedule decoded from the captured live YASNO response into the real App Group container, selected group `19.1`, set YASNO display mode, and requested `WidgetCenter.reloadAllTimelines()`.
- Xcode then launched the WidgetKit extension separately through `OutageScheduleWidget`. Actual Small and Medium widgets displayed group `19.1` and its timeline on SpringBoard. This confirms the extension process read the shared snapshot written by the app-host test process.
- App Group container identity was also checked through the installed app's simulator container information. The test `testSimulatorAppGroupPersistsScheduleBetweenStoreInstances` independently passed by writing through one `ScheduleStore` and reading through another.
- WidgetKit timeline invalidation was requested and the resulting widgets showed the updated live group snapshot. This verifies a successful update cycle; it does not establish how quickly WidgetKit will honor reload requests under system load.
- Invalid/corrupt and missing snapshot fallback remain covered by deterministic tests and the actual no-data Home Screen state. Existing saved user data was preserved and restored after visual experiments.

## Widget visual inspection — **PARTIAL**

Actual Home Screen screenshots show both widget families together:

- [Live YASNO, light appearance](phase3_1-evidence/widget-yasno-light.png)
- [Live YASNO, dark appearance](phase3_1-evidence/widget-yasno-dark.png)
- [No-data fallback, light appearance](phase3_1-evidence/widget-empty-light.png)
- [Stale demo snapshot, light appearance](phase3_1-evidence/widget-stale-light.png)
- [App clean-install empty state](phase3_1-evidence/clean-install-empty-state.png)

The live schedule shows current state, the full-day timeline, current-time marker, group identity, freshness label, and the group-level caveat. Small and Medium fit without clipping in the captured live state. Dark appearance preserves readable contrast. No-data fallback and stale schedule presentations were seen in light appearance.

The live schedule at capture time had no further transition that day; it correctly showed “Змін більше немає”. A synthetic manual snapshot with a near-future transition was placed in the simulator container, but direct filesystem edits did not cause WidgetKit to replace its cached timeline. After a simulator reboot, the Home Screen recovered, but the extension scheme no longer placed the widget automatically. The original saved snapshot was restored. Therefore an upcoming countdown and countdown layout are **BLOCKED / NOT VISUALLY VERIFIED**. No countdown screenshot is claimed.

Visual defects fixed after observing the real widget:

- Small YASNO header/status were too wide and were ellipsized. The compact header is now `YASNO` (group key remains on its detail line), with shorter compact status labels.
- The address-oriented group disclaimer was clipped. Both sizes now use the shorter explicit group-level caveat, “Group-level schedule; actual outages may differ.”
- Clean install previously treated a missing snapshot as shared-storage failure. `restore()` now checks App Group availability, avoiding a false save error before the user has saved a schedule.

## Regression verification

Commands run from the repository root:

```text
xcodebuild build -project OutageSchedule.xcodeproj -scheme OutageSchedule -configuration Debug -destination 'platform=iOS Simulator,id=39BD58BC-C407-4097-B8A6-7E1FC0BD599A' -derivedDataPath /tmp/phase31-derived CODE_SIGNING_ALLOWED=YES CODE_SIGNING_IDENTITY=-
xcodebuild test -project OutageSchedule.xcodeproj -scheme OutageSchedule -configuration Debug -destination 'platform=iOS Simulator,id=3730FF5E-C4E9-4E60-856A-797D8790D666' -derivedDataPath /tmp/phase31-derived CODE_SIGNING_ALLOWED=YES CODE_SIGNING_IDENTITY=-
plutil -lint OutageSchedule/OutageSchedule.entitlements OutageSchedule/OutageScheduleWidget.entitlements
git diff --check
```

- App and embedded widget build: **PASS**.
- Full XCTest suite: **PASS**, 27 tests, 0 failures on iPhone 18 Pro. A run on iPhone 15 Pro first failed before test connection because the XCTest host was killed; rerunning the unchanged suite on iPhone 18 Pro succeeded. This is recorded as a simulator-specific launch failure, not a test assertion failure.
- Entitlement plist lint: **PASS**.
- No existing tests were weakened or removed. Three temporary seed/clear test methods used during simulator setup were removed before final regression run.
- Result bundle from the final full suite: `/tmp/phase31-derived/Logs/Test/Test-OutageSchedule-2026.11.14_10-41-45-+0100.xcresult`.

## Remaining limitations and status

| Verification area | Status | Notes |
|---|---|---|
| Live YASNO compatibility | **PASS** | Exact public endpoints and captured response format verified on 2026-11-14. |
| App Group configuration and app-to-widget read | **PASS** | Real app-host write and separate WidgetKit extension render verified on simulator. |
| Small/Medium and light/dark widget visuals | **PASS** | Both families inspected in live state for light/dark; no-data/stale inspected in light. |
| Upcoming countdown rendering | **BLOCKED** | Live data had no next transition; synthetic state did not replace cached timeline. |
| Resilience to provider outage | **PASS by deterministic coverage** | Live service failure was not induced; fixture tests exercise failure handling. |

The remaining visual limitation is the countdown state. Provider availability and response structure may change after this dated capture. WidgetKit can defer reload requests, so the observed update does not imply a fixed refresh latency.

## Files changed

- `OutageSchedule/App/ContentView.swift`, `OutageSchedule/Shared/Storage/ScheduleStore.swift`: correct clean-install shared-storage availability state.
- `OutageSchedule/Widget/WidgetViews.swift`: compact YASNO labels and readable group-level disclaimer.
- `OutageScheduleTests/ScheduleDomainTests.swift`: live-capture compatibility and real App Group persistence coverage.
- `OutageScheduleTests/Fixtures/yasno-live-regions.json`, `yasno-live-planned-outages.json`: sanitized live captures.
- `OutageSchedule.xcodeproj/project.pbxproj`: test fixture resources.
- `OutageSchedule.xcodeproj/xcshareddata/xcschemes/OutageScheduleWidget.xcscheme`: repeatable extension launch scheme for simulator visual validation.
- `README.md`, `docs/PHASE_3_VERIFICATION.md`, this report, and `docs/phase3_1-evidence/` screenshots.
