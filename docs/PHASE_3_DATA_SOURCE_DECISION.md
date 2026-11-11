# Phase 3A.1 Data Source Decision & Feasibility Assessment

**Date:** 2026-11-11  
**Scope:** Research and decision only. No source code, project configuration, or previous findings were changed.

## Decision

### Recommended MVP: user-configured schedule, sourced by the user from an official channel

For a useful working application without claiming unsupported live accuracy, the MVP should let the user enter/select their address and configure the schedule intervals they have just verified through an official DTEK channel. Store the schedule for its effective date, record when the user last verified it and where, and label it clearly as **user-entered / last checked**, not as a live DTEK feed. Provide a direct link or instruction to check the official source again. If the schedule has no reliable current value, show “no current schedule” and keep the widget unavailable state; do not fill gaps with assumed availability.

DTEK is the authoritative target for individual Kyiv address schedules, but no supported DTEK machine-readable interface has been verified. A provider-backed, automatically refreshed MVP cannot safely begin today. This user-assisted mode provides an honest, useful schedule widget while preserving a path to a future approved remote source.

**Important product distinction:** this is technically functional schedule display, but its accuracy depends on the user transcribing the current official schedule correctly and refreshing it after DTEK changes it. It is not an authoritative integration, a real-time status indicator, or proof that electricity is physically present. DTEK itself says schedules can change at any time and describes them as a day-ahead forecast. [DTEK's official shutdown page](https://www.dtek-kem.com.ua/ua/shutdowns?page-limit=25) directs customers to its site/chatbots and Kyiv Digital for address schedules.

### Phase 3B readiness

**Phase 3B cannot safely begin as an automatic provider integration.** It can begin only after approval of a scoped user-configured MVP, with the product labels and data-entry behavior described above. If the desired Phase 3B outcome is live authoritative schedules, wait until an official supported API/feed or an approved machine-access agreement is established and verified. Do not use undocumented endpoints, scrape website flows, or bypass WAF protections.

## Options assessed

| Option | Accuracy | Address-level support | Technical feasibility | Reliability and maintenance | Decision |
|---|---|---|---|---|---|
| **A. Direct YASNO API** | The API returns real schedule data, but the live-verified planned endpoint is group-keyed (`1.1`, `2.1`, etc.). Phase 0 verified house-to-group resolution; it did not verify that those group records represent DTEK's current per-address schedule. The November 11 response also had a five-minute public cache header while `updatedOn` lagged the response by about 20 hours. | Address resolver exists and returns one group/subgroup in the Phase 0 examples. That is not proof of an individual-address schedule. YASNO's current public Kyiv outage page now presents street/building address inputs and states that one address can return two graphs. The relationship between that UI and the tested group-keyed API is unverified. | Straightforward native `URLSession` GETs were verified without authentication for the tested endpoints. No browser CORS issue. No documented API contract, rate limit, or SLA was found. | Easy to prototype; medium/high ongoing risk from undocumented schema, freshness ambiguity, and potentially changed schedule semantics. Must re-verify source mapping and update cadence. | **Reject as direct data provider for address-accurate MVP for now.** Reconsider only if YASNO documents or authoritatively confirms the tested endpoint's current address applicability and schedule semantics. The public UI may be useful for user-assisted verification. |
| **B. Official DTEK API/feed** | Highest potential: DTEK is the distribution operator and its official page says individual address schedules can differ, can have two feed graphs, and can change during the day. | Explicitly address-specific in official website experience. Multiple feeds can exist per building; residents may need building management to identify their apartment's feed. | No supported machine interface verified. Direct request currently yields Incapsula challenge HTML, not an API response. Authentication/access rules, schema, cadence, and rate limits unknown. | Best semantic authority, but implementation and operations are currently blocked. An unsupported interface could break without notice; WAF bypass is prohibited. | **Preferred future automatic provider, conditional on supported access. Not ready to implement.** |
| **C. User-assisted configuration from official schedule** | Potentially high for the date/time the user verifies if entered accurately; transcription mistakes and later source changes remain possible. User may be unable to determine which of two building feeds applies. | User can enter their address and one or more schedule variants. Applicability is user-confirmed; when uncertain, the UI must preserve that uncertainty and avoid choosing a feed on the user's behalf. | Low/moderate. Existing domain supports dated intervals and multiple `AddressSchedule` entries. Requires an interval editor, date and source-check metadata, persistence, and clear stale/unavailable presentation. No network dependency. | No endpoint maintenance. Ongoing user burden and risk of stale/manual data. Needs explicit “last verified” date and easy correction. | **Recommended interim MVP**, if product accepts manual entry and honest labeling. |
| **D. Official Kyiv Digital, DTEK website or chatbot as another source** | Official channels are authoritative for the values presented to the user. No evidence found here of a supported public machine-readable API for these channels. | DTEK says its website, bots, and Kyiv Digital can provide address results. | Feasible for the user to consult manually; automation/API access is unverified. Account-linked bots may require user registration and may be inappropriate to call from a third-party app. | Low integration maintenance if linked/opened for manual lookup; high and unacceptable maintenance/policy risk if scraped or reverse-engineered. | **Use as a user handoff/source, not as an automated app provider.** |
| **E. Community clients / third-party aggregators** | Varies by source; can lag, mis-map addresses, or depend on unofficial interfaces. No independent authority guarantee established. | Some claim address/group support; no approved accurate interface established for this project. | Often technically accessible through reverse-engineered endpoints, but accessibility does not establish permission or durability. | High upstream breakage and provenance risk; adds another service dependency and can inherit WAF issues. | **Reject for MVP.** Reconsider only with a documented, reputable source contract and independently validated address mappings. |
| **F. DTEK server proxy/backend** | Same upstream accuracy as the source; proxying does not improve data truth. | Same as DTEK source. | No supported backend-accessible upstream is known. | Adds hosting, privacy, security, and operational cost without resolving access authorization. | **Reject now.** Consider only if DTEK explicitly supports a server feed or credentials/caching requirement makes a backend necessary. |

### YASNO public page vs YASNO API

YASNO's current public outage page exposes street/building fields and includes FAQ topics about two schedules for one address and schedule changes. This is meaningful evidence that a human-facing address lookup is offered by YASNO. It does **not** prove that the previously tested public API's group-keyed planned-outages response is the backend for that lookup, or that the group's schedule is an exact equivalent to the displayed individual result. This is a distinct unresolved question. The API should not be assumed accurate for address-specific schedules based on the UI alone.

## Architecture implications

The architecture proposed in [PHASE_3_ARCHITECTURE.md](PHASE_3_ARCHITECTURE.md) remains a good future remote-provider boundary, but implementing its `OutageDataSource`, remote client, DTOs, and refresh coordinator now would be unnecessary complexity because no approved remote provider is ready.

### For the recommended manual MVP

- **`OutageDataSource`:** defer it. Manual data entry is not a remote data source. Do not create a protocol solely to satisfy an abstract architecture diagram. Add it when an approved automated source exists.
- **Internal schedule models:** `SelectedAddress`, `ScheduleInterval`, `AddressSchedule`, and multiple schedule entries already represent address/date/interval/alternative feed data. The current `ScheduleStatus.unknown` can express unknown intervals. The snapshot lacks explicit provenance and checked time. Add only the minimum metadata the UI needs, such as `sourceKind = userEntered`, `lastVerifiedAt`, and optionally a source label/link. `fetchedAt` should retain its literal meaning (time persisted/fetched) and must not be relabeled as the provider update time.
- **Schedule completeness:** do not infer `.available` for gaps unless the user marks a complete daily schedule and confirms that omission means power is on. If the source provides only outage periods, render only known outage ranges and unknown elsewhere, or require complete on/off segmentation. The selected rule must be explicit.
- **`ScheduleStore`:** current atomic JSON App Group storage is sufficient for a single user's local manual schedule. If adding non-optional Codable fields, bump `schemaVersion` and migrate version 1 or decode old snapshots safely. Avoid a second database or backend. A typed save error is optional; the current `Bool` is sufficient to show a general persistence error in a small MVP, though tests should verify failed writes preserve the old file.
- **User configuration:** add address entry/confirmation, effective schedule date, interval configuration, optional multiple schedule variants, user selection of the applicable variant, and last-verified/source fields. For a multi-feed building, show that the user must verify the applicable feed with the building manager/OSBB; never pick one arbitrarily. Manual entry should be explicitly user-authored and editable.
- **Error/unavailable states:** distinguish at least `No schedule configured`, `Schedule expired/not checked for current date`, `Unknown applicable feed`, and `Storage unavailable`. Existing empty schedules and `.unknown` can render unavailable, but without a reason/provenance field the app cannot explain why. Preserve a last-known-good prior day only as historical context; do not display it as today's schedule.
- **Widget:** continue offline-only. It reads the persisted snapshot and labels user-entered data and last-check date (or displays unavailable when no current data exists). Widget reload occurs only after successful save.
- **Mock scenarios:** retain all existing `MockScheduleFactory` behavior separately from any user-entered schedule. Do not silently seed mock schedules into a live/manual configuration state.

### If a provider becomes approved later

Add the minimal `OutageDataSource` protocol, URLSession client, provider DTOs, validator/mapper, and app refresh coordinator in the main app target. Keep the widget on the shared normalized snapshot. A provider-backed schedule should preserve source identity and provider update time separately from local fetch time, with migration/tests for the existing schema. Keep manual configuration as a fallback only if product explicitly wants that mode.

## Required user/product input before implementation

Approve or reject the manual-entry MVP. If approved, confirm:

1. Is the intended geography Kyiv City only?
2. Will users enter full on/off intervals or only outage periods? Full intervals are clearer if the app must label power-on time; outage-only input needs unknown states outside entered windows.
3. Should users enter one schedule or support multiple feed variants and select the applicable one?
4. What is the freshness rule: expire at local end of schedule date, or require a user recheck at a chosen interval? DTEK says schedules can change at any time, so no automatic freshness guarantee exists.
5. Which official handoff should be shown: DTEK shutdown page, DTEK chatbot, Kyiv Digital, or allow the user to choose? DTEK currently lists these as official channels.

No user personal account, API token, or address should be sent to an unapproved third party. Address persistence remains local in App Group storage unless scope/privacy review explicitly changes that.

## Conditions before Phase 3B

### If Phase 3B means manual user-configured schedule MVP

It may start only after explicit approval of this changed scope and decisions above. Implementation must:

1. Label all entered schedules as user-provided and show the last verification date.
2. Avoid claims of automatic or real-time DTEK data.
3. Preserve unknown/unavailable intervals and never infer power-on from missing data without confirmation.
4. Handle multiple schedules without choosing an unverified building feed.
5. Keep snapshot writes atomic, preserve prior data on save failure, and leave the widget network-free.
6. Test persistence/schema migration, invalid/overlapping intervals, stale dates, unknown feed selection, and unavailable/storage-failure states.

### If Phase 3B means automatic real-data integration

Do not start until all of the following are met:

1. DTEK or YASNO confirms a supported machine-readable interface and permitted use, or another authoritative source documents the same.
2. The endpoint is reachable without WAF circumvention and its current response is captured as a sanitized real fixture.
3. Address-to-schedule mapping is verified for multiple addresses and multi-feed cases.
4. Status meanings, completeness, update timestamps, timezone behavior, freshness, quotas, and failure semantics are documented.
5. A real address can be tested with the user/provider's authorization and no invented residential examples.

## Sources and evidence

- [Phase 0 findings](PHASE_0_FINDINGS.md) — live YASNO API/address-resolution fixtures and DTEK direct challenge findings dated 2026-11-07.
- [Phase 3A research](PHASE_3_DATA_SOURCE_RESEARCH.md) — repeat YASNO and DTEK HTTP checks dated 2026-11-11; group-keyed YASNO API payload and freshness observation.
- [DTEK Kyiv official shutdown page](https://www.dtek-kem.com.ua/ua/shutdowns?page-limit=25) — address UI; states address schedules are individual, some buildings have two feed schedules, published schedules can change, and directs users to DTEK website/chatbots and Kyiv Digital.
- [DTEK official Kyiv Digital announcement](https://admin-stage2.dtek-kem.com.ua/ua/news/u-kiyevi-diyut-individualni-grafiki-vidklyuchen-shcho-vazhlivo-znati-kiyanam) — says each address has a personal schedule and identifies DTEK official services/Kyiv Digital.
- [DTEK chatbot information](https://admin-stage2.dtek-kem.com.ua/ua/chatbot) — official chatbot channel; no public API contract established.
- [YASNO Kyiv outage page](https://static.yasno.ua/kyiv/outages) — human-facing address lookup and FAQ about two schedules per address; does not document the tested group's API as an integration contract.
- [YASNO live regions endpoint](https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/regions) and [planned schedule endpoint](https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages) — publicly accessible responses live-verified as recorded in Phase 3A; no support commitment identified.

## Final recommendation

Approve **user-assisted manual configuration** as the interim MVP if a working widget is needed before an official API is available. Treat its schedule as user-entered and dated, not automatically authoritative. Reject direct YASNO API integration for the current address-accuracy claim; defer DTEK automation pending a supported interface; do not add a backend or third-party scraper.

**Stop here for approval.** Phase 3B implementation has not started.
