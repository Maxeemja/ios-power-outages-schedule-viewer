# Phase 3 Final Verification

## Current simulator verification — 2026-11-14

CoreSimulator access is available in this execution context. `xcrun simctl list devices available` reported the iPhone 18 Pro (`3730FF5E-C4E9-4E60-856A-797D8790D666`) as **Booted** on iOS 27.2. Xcode reports version 27.2 (build 27B52).

Commands run from the repository root:

```text
xcodebuild build -project OutageSchedule.xcodeproj -scheme OutageSchedule -destination 'platform=iOS Simulator,id=3730FF5E-C4E9-4E60-856A-797D8790D666' -derivedDataPath /tmp/phase3-outage-derived CODE_SIGNING_ALLOWED=NO
xcodebuild test -project OutageSchedule.xcodeproj -scheme OutageSchedule -destination 'platform=iOS Simulator,id=3730FF5E-C4E9-4E60-856A-797D8790D666' -derivedDataPath /tmp/phase3-outage-derived CODE_SIGNING_ALLOWED=NO
```

- Build: **PASS** (`** BUILD SUCCEEDED **`). The scheme built the app and its WidgetKit extension for iOS Simulator.
- Tests: **PASS** (`** TEST SUCCEEDED **`); all 25 XCTest methods executed on the iPhone 18 Pro with 0 failures.
- Test result bundle: `/tmp/phase3-outage-derived/Logs/Test/Test-OutageSchedule-2026.11.14_9-47-47-+0100.xcresult`.
- `git diff --check`: **PASS**.

This supersedes the earlier simulator-unavailable attempts recorded below. No source or test failure was encountered in this run. Runtime UI inspection, cross-process App Group behavior, and a live YASNO request remain outside the automated verification performed here.

## Follow-up verification run — 2026-11-14

The requested simulator commands were rerun with the provided scheme, simulator UUID, and derived data path:

```text
xcodebuild build -scheme "OutageSchedule" -destination 'platform=iOS Simulator,id=3730FF5E-C4E9-4E60-856A-797D8790D666' -derivedDataPath /tmp/OutagesDerivedData CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme "OutageSchedule" -destination 'platform=iOS Simulator,id=3730FF5E-C4E9-4E60-856A-797D8790D666' -derivedDataPath /tmp/OutagesDerivedData CODE_SIGNING_ALLOWED=NO
```

Both invocations started, but this environment reported that CoreSimulatorService was disconnected, `simdiskimaged` was unavailable, and no simulator runtimes were discoverable. Neither invocation reached a build or XCTest result before it was interrupted after stalling. Therefore this follow-up run establishes **neither a successful build nor a test pass**. The 25 test methods are present in the test target, but were not executed in this run. `git diff --check` passed.

This was an earlier attempt before CoreSimulator access was restored. The current simulator verification above supersedes this result.

### Coverage review

- Existing tests cover fixture-based YASNO mapping, provider group-key discovery, invalid/missing group and slot data, HTTP/content-type/redirect/transport failures, waiting state, manual/YASNO storage separation, selected-group persistence, last-known-good protection for older provider timestamps, freshness boundaries, and manual/YASNO timeline expiration policy.
- Remaining verification gaps: no running-app exercise of group selection and refresh; no cross-process App Group check; and no widget UI snapshot/presentation tests or visual inspection. Endpoint construction from live YASNO metadata and current live API compatibility also remain unverified here.

## External verification attempt — 2026-11-14

- Xcode is installed: `xcodebuild -version` reports Xcode 27.2 (build 27B52).
- Simulator availability check: `xcrun simctl list devices available` failed. CoreSimulatorService disconnected (`Connection refused` / `Connection invalid`), `simdiskimaged` could not start, and Xcode reported that no simulator runtimes were discoverable. Simulator services are unavailable in this environment.
- XCTest execution attempt: `xcodebuild test -project OutageSchedule.xcodeproj -scheme OutageSchedule -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`. Xcode initialized with simulator support disabled and produced no test-run output; the process remained stalled, so it was interrupted. No XCTest test executed and no pass/fail result is claimed. The existing `build-for-testing` result below is compile-only evidence.
- Live YASNO attempt: requested the documented planned-outages route for region `25`, DSO `902` using `curl --max-time 15`. DNS resolution failed (`Could not resolve host: app.yasno.ua`, HTTP `000`), so this environment could not reach the live service. No mock response was used.
- Small/Medium widget launch, visual inspection, manual schedule behavior, group selection, freshness/expiration/fallback behavior, and cross-process App Group persistence could not be exercised without a running simulator or attached supported device. No physical device was available through the inspected Xcode/simulator tooling.

These are historical environment blockers from an earlier execution context. The current run below verifies the simulator build and XCTest suite, but does not close the listed live-service and visual/runtime coverage gaps.

## Status

The simulator app and WidgetKit extension build and all 25 automated tests pass. Runtime product acceptance still needs the external checks listed below: app/widget shared-storage exercise, visual inspection, and live YASNO compatibility. CoreSimulator is available in this execution context.

## Implemented functionality

- Manual schedule entry, editing, selected schedule persistence, and a two-hour verification freshness window.
- YASNO group discovery, schedule fetch, subgroup-preserving mapping, explicit waiting state, and freshness presentation.
- Separate App Group files for the manual schedule, each YASNO group, and YASNO waiting state; mode and selected group are stored in shared defaults.
- Last-known-good YASNO schedule preservation when older provider data arrives or a fetch fails.
- Small and Medium widget layouts with current status, next transition/countdown, freshness or unavailable state, and scheduled timeline entries.
- Kyiv-local day calculations including DST day length.

## Verification performed

- Generic iOS Simulator build (app and WidgetKit extension): **PASS**.
- Generic iOS device SDK build: **PASS**.
- `build-for-testing` for the XCTest bundle: **PASS**; 25 test methods compile.
- Xcode static analysis (`analyze -quiet`): **PASS**, no analyzer findings.
- `git diff --check`: **PASS**.
- Static review covered response status/URL/content type/body decoding, metadata-derived region/DSO mapping, subgroup keys, complete contiguous slot coverage, day validation, manual/YASNO storage isolation, sequential last-known-good protection, freshness cutoffs, user-facing fetch errors, App Group entitlement parity, widget family states, transition generation, and Kyiv/DST date handling.
- Deterministic regression tests were added for manual expiry fallback, the exact freshness cutoff transition, YASNO availability despite old manual verification, generated schedule transitions, and unavailable fallback when no source is valid.
- XCTest execution: **PASS**, 25 executed, 0 failures (current simulator verification above).
- Live YASNO requests were not part of this audit; fixture-based tests executed successfully, but do not prove current live API compatibility.

## Audit findings and limitations

- Manual freshness now gates only manual timelines. YASNO mode calculates no manual expiry, so an old manual verification cannot suppress valid YASNO transitions.
- A manual transition at the exact two-hour cutoff is included. Manual freshness is inclusive at the cutoff; the unavailable fallback entry is scheduled one second later.
- Provider response validation fails closed for bad status, redirect URL changes, non-JSON MIME types, malformed payloads, unrecognized statuses/types, incomplete or non-contiguous slots, invalid dates, and stale/future update timestamps.
- YASNO and manual snapshots use separate files. App and widget entitlements declare the same App Group identifier. Actual signed-device entitlement access is not verified.
- Last-known-good comparison is a sequential read/compare/write and is not cross-process serialized. Two simultaneous app refreshes could race; atomic file replacement protects file integrity but does not make that sequence transactional.
- WidgetKit controls actual refresh timing and may defer requested timeline refreshes. External runtime validation must confirm behavior on supported iOS versions.
- Small/Medium layout, accessibility, stale/waiting/unavailable appearance, and timeline delivery have not been visually or behaviorally inspected in a running widget.
- API availability and response compatibility can change; this verification does not prove current live endpoint operation.
- The project has existing Xcode warnings about `UIDeviceFamily` in the widget plist and app orientation declarations; no unrelated settings were changed.

## External runtime validation required

- Install/run on a supported iOS device or a functioning simulator; validate shared App Group persistence across app and widget processes.
- Inspect Small and Medium widgets in available, outage, possible, stale, waiting, and unavailable states.
- Confirm transition entries render at each interval boundary and manual expiry updates the widget to unavailable.
- Exercise YASNO group discovery and schedule refresh against the live service, including waiting and network/server error behavior.
- Validate concurrent refresh behavior if simultaneous app refreshes can be initiated in the product.

## Acceptance checklist

- [x] Generic iOS app build.
- [x] Generic WidgetKit build.
- [x] XCTest bundle compilation (25 tests; no execution claim).
- [x] Xcode static analysis.
- [x] `git diff --check`.
- [x] Manual expiration cannot suppress YASNO transitions by policy; deterministic regression coverage compiles.
- [x] Manual expiry, YASNO availability, transition generation, exact cutoff, and invalid-source fallback regression cases added.
- [x] API validation, group mapping, storage separation, freshness, error handling, widget states, App Group declarations, and date handling reviewed.
- [x] XCTest suite executes and passes (25 tests, 0 failures, iPhone 18 Pro simulator).
- [ ] Runtime YASNO and shared-storage behavior verified on device/simulator.
- [ ] Small and Medium widgets visually inspected in all relevant states.
- [ ] Phase 3 fully accepted.
