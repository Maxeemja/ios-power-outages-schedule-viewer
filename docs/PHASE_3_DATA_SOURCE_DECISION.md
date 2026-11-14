# Phase 3 Data Source Decision

**Decision status:** Current product decision, superseding the November 11, 2026 address-specific/manual-MVP recommendation below in the research history.
**Approved scope:** YASNO group schedule as the primary automatic Phase 3 source.
**Decision date:** As recorded by the product owner in the Phase 3 plan revision.

## Approved decision

Phase 3 will automatically load and display a user-selected YASNO group schedule. The product is a group schedule, not an address-specific outage schedule. The user must see that the schedule applies to the selected group and that actual outages at an individual building or apartment may differ. A YASNO address-to-group mapping, if offered, identifies a group only; it does not verify an address-specific schedule.

DTEK address-specific automatic integration is out of scope and does not block Phase 3. No DTEK edge-protection investigation, scraping, browser automation, or bypass is authorized or required. This decision changes the product scope from the earlier address-specific requirement; historical findings remain useful only as evidence and constraints.

## Evidence and trade-offs

The existing [Phase 0 findings](PHASE_0_FINDINGS.md) and [Phase 3 data source research](PHASE_3_DATA_SOURCE_RESEARCH.md) record live unauthenticated YASNO GET responses for region metadata and planned group schedules. The observed schedule endpoint is keyed by group strings such as `19.1` and contains day records with slots, dates, statuses, and `updatedOn`. Two provider-resolved samples mapped to groups `19.1` and `37.1`. These facts support a group schedule product, not an individual-property accuracy claim.

The endpoint is technically callable in the observed checks, but it is undocumented and has no verified SLA, quota, or compatibility promise. The observed five-minute cache header did not guarantee current schedule data: the November 11 sample's `updatedOn` lagged the HTTP `Date` by about 20 hours. The app must use provider update metadata for freshness, preserve the last valid snapshot, and report stale/unavailable data honestly.

No backend is currently required by the observed public GET flow. Keep requests in the main app and the widget offline. Reconsider a backend only if a supported provider requirement later demonstrates a need; do not add one to compensate for undocumented behavior.

## Historical decision record

The November 11, 2026 assessment recommended a user-configured manual schedule because the original product requirement was address-specific and no supported DTEK machine interface had been verified. It also rejected the then-known YASNO group data for that address-specific claim. The product owner has since explicitly approved group schedule semantics, removing that mismatch as a Phase 3 blocker. The historical DTEK and YASNO evidence remains unchanged in [Phase 0 findings](PHASE_0_FINDINGS.md); it must not override the approved group-level product definition.

## Architecture consequences

- Preserve the `OutageDataSource → Remote Client → Response Mapper → ScheduleStore → Widget` boundary.
- Persist selected YASNO group identity, source update time, and client fetch time distinctly. The current model is manual/address-oriented and has no YASNO group identity; any minimal additive model/schema migration must preserve existing manual snapshot behavior.
- Keep `MockScheduleFactory`; do not conflate demos with provider data.
- All network work remains in the main app. Widget consumes a local last-valid snapshot only.
- Invalid, stale-rejected, waiting, or failed responses never fabricate availability or erase last-known-good data.
- Show the selected group and a clear building/apartment applicability disclaimer in app and widget.

Detailed provider facts and uncertainties are in [Phase 3 research](PHASE_3_DATA_SOURCE_RESEARCH.md); component responsibilities are in [Phase 3 architecture](PHASE_3_ARCHITECTURE.md); task acceptance and tests are in [Phase 3 implementation plan](PHASE_3_IMPLEMENTATION_PLAN.md).

## Approval and implementation status

The provider/product decision is approved. This documentation revision does not authorize application-code implementation by itself; implementation remains pending explicit approval under the project workflow. The previously reported SwiftUI `@State` macro-plugin malformed response and unavailable simulator services remain unresolved environment issues, not established application defects. Do not change signing, provisioning, or unrelated Xcode settings to work around them.
