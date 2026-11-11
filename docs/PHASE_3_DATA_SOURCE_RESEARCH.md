# Phase 3A Data Source Research

**Research date:** 2026-11-11  
**Scope:** Read-only provider investigation and architecture input. No source code, project configuration, or existing fixtures were changed.  
**Fresh HTTP checks:** unauthenticated GET requests to YASNO planned schedule and regions endpoints, and DTEK Kyiv's official shutdown page. The requests were read-only.

## Recommendation

DTEK Kyiv is the correct authority to investigate for the application's address-specific schedule, but it is **not yet an implementable provider**: a current machine-readable endpoint, access policy, and schema have not been verified. Phase 3B should begin with an explicit integration gate: obtain or verify a supported, stable DTEK data interface that can return the selected address's schedule without defeating the site's edge controls. Until then, retain the mock data path and do not label YASNO group data as an address-specific DTEK schedule.

YASNO is technically callable by native `URLSession` and currently returns live JSON, but its tested endpoint is still keyed by groups (`1.1`, `2.1`, etc.) and describes `today`/`tomorrow` group schedules. DTEK's official product information describes individual schedules per address, possible two-feed schedules for one building, and a schedule that can change at any time. That is a material semantic mismatch, not a transport issue.

## Current verification

| Source / request | Current result (2026-11-11) | Verified facts and limits |
|---|---|---|
| YASNO `GET /api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages` | HTTP 200, JSON, 28,952-byte body; `Cache-Control: max-age=300, public`; response `Date: Wed, 11 Nov 2026 16:21:34 GMT` | Unauthenticated request succeeded. The object is keyed by queue strings such as `1.1`, `2.1`. A day record includes `slots` (`start`, `end`, `type`), `date`, `status`, and `updatedOn`. In the response, today was 2026-11-11, tomorrow had `WaitingForSchedule` with empty slots, and `updatedOn` was 2026-11-10T20:00:02Z. HTTP success/cache age does not establish schedule freshness. |
| YASNO `GET /api/blackout-service/public/shutdowns/addresses/v2/regions` | HTTP 200, JSON, `Cache-Control: max-age=300, public` | Unauthenticated request succeeded. Current response listed region `id: 25`, `value: Київ`, and DSO `id: 902`, named DTEK Kyiv Electricity Networks. This establishes current region/operator metadata only, not an address-to-schedule equivalence. |
| DTEK `GET https://www.dtek-kem.com.ua/ua/shutdowns` | HTTP 200, `text/html`, `Cache-Control: no-cache, no-store`; body 205 bytes | Body is an Incapsula bootstrap/challenge page with `robots noindex,nofollow`; it is not the page application or schedule API. No AJAX calls or schema can be verified from this response. Do not automate or bypass the challenge. |

The prior Phase 0 report, [PHASE_0_FINDINGS.md](PHASE_0_FINDINGS.md), includes dated sanitized real YASNO fixtures, address resolver responses, and a previous direct DTEK challenge result. These are historical evidence, not a promise that the same YASNO fields or endpoint behavior will persist. No new fixture is added here because the requested deliverables are architecture documents and the current schedule response contains data that is not useful as a stable test expectation. Fixtures for implementation should be captured and sanitized when a provider/schema is approved.

## Provider comparison

| Criterion | YASNO public blackout API | DTEK Kyiv official address lookup |
|---|---|---|
| Authority/model fit | The region names DTEK Kyiv Networks, but the tested schedule is group-keyed. Fit for today's individual-address schedule is not established. | Official source for the target operator. Official page says each address has an individual schedule; some buildings can yield two schedules because of multiple feeds. |
| Live machine access | Verified unauthenticated GETs for region metadata and planned group schedules. | Not verified: current direct page fetch returns an edge challenge, not usable content or API response. |
| Address flow | Phase 0 verified street → house → group for two Kyiv samples. It returned a single group/subgroup, which does not encode DTEK's documented multi-feed case. Current Phase 3 check only reverified regions and schedule, not all resolver steps. | Official web experience asks for street then building. Current lookup request sequence and response shape remain unknown. |
| Response / schedule semantics | Group-keyed object; day slots use minute-of-day integers and types such as `Definite` and `NotPlanned`; day status includes `ScheduleApplies` and `WaitingForSchedule`. | Official site describes day-ahead address schedule. Current DTO, timezone representation, slot semantics, multi-feed IDs, and update metadata unknown. |
| Authentication and restrictions | No token/session was needed for tested GETs. No published SLA, quota, or compatibility contract was identified. | Unknown for a successful machine request. Site edge challenge is an access/reliability barrier; do not treat reverse-engineered browser/AJAX behavior as permission to automate. |
| Freshness | Schedule response advertises five-minute public cache; current `updatedOn` lagged response date by about 20 hours. It is not a freshness guarantee. | Official page says schedule is only forecast a day ahead and can change at any time; also says high concurrent traffic can cause delay up to five minutes. Exact machine timestamps unknown. |
| Direct iOS feasibility | Technically viable for raw GET requests; no browser CORS limitation applies to native `URLSession`. Product semantics and undocumented API maintenance remain blockers. | Unknown. Do not implement until a supported endpoint is shown to work from an ordinary client/server without WAF circumvention. |

## Decision and trade-offs

1. **Preferred authority: DTEK Kyiv, conditional on a supported machine interface.** It matches the individual-address product model and is the source users are directed to for current address schedules. Its current official page says neighboring buildings can differ, a building can have two feeds, schedules are day-ahead, and emergency/system changes can invalidate the published plan.
2. **Do not use YASNO as the primary source for this widget's asserted address schedule.** Its endpoints remain useful for investigation or a separately labeled group schedule, but a successful request does not prove the result applies to the current DTEK address-level schedule. Mixing its group schedule into an address-specific product could confidently display the wrong outage periods.
3. **No backend now.** A backend cannot cure a source that is not authorized or stable and should not be used to bypass the DTEK edge challenge. If DTEK later provides a supported feed that requires server-side credentials, aggregation, or permitted caching, revisit a small adapter then. If a supported public endpoint works for direct `URLSession`, direct app refresh is the simpler initial option.
4. **Refresh expectations must be conservative.** A source can change during the day and may only publish tomorrow's plan. The app should retain last-known-good data with a visible source/update time and freshness state; the widget should never fetch the network itself.

## Reliability and maintenance risks

- Undocumented YASNO endpoints can change without notice or usage guarantees; response metadata currently demonstrates that a five-minute CDN cache is not equal to a recent underlying schedule update.
- DTEK edge protection may make automated requests unavailable. An HTTP 200 challenge HTML response must be treated as a protocol failure, not as an empty schedule.
- Official schedules are forecasts and can change after an аварія, overload, or grid incident; a schedule is not real-time proof that power is physically available.
- DTEK's multiple-feed case requires representing more than one schedule for one address and cannot be collapsed to a single arbitrary choice. The existing `AddressSchedule` collection and `selectedScheduleID` can represent alternatives, but the app's selection UX needs a product decision.
- Address spelling, renames, house variants, missing addresses, and address selection ambiguity need provider-returned identity/labels rather than locally guessed IDs.
- Offline state, invalid HTML/JSON, partial/missing days, changed timezone formats, and timestamps with stale or future values must preserve last-known-good storage and be visible to app/widget logic.
- No provider quota, service-level agreement, or long-term compatibility commitment has been established by this research.

## Source links

- [DTEK Kyiv official shutdown page](https://www.dtek-kem.com.ua/ua/shutdowns) — current address lookup and explanatory content; direct HTTP response in this research was only an edge challenge.
- [YASNO live regions endpoint](https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/regions) — current live HTTP response verified on 2026-11-11.
- [YASNO live planned schedule endpoint](https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages) — current live HTTP response verified on 2026-11-11.
- [Phase 0 findings](PHASE_0_FINDINGS.md) — prior tests, sanitized fixtures, and historical limitations.

## Unresolved questions / Phase 3B gate

1. Will DTEK provide or authorize a documented machine-readable interface/feed for address schedule lookup, and what are its terms and rate limits?
2. Can that interface be called directly from a native app, and does it return access challenges to ordinary clients? What authentication, if any, is officially supported?
3. What are the current address, schedule, multi-feed, status, timezone, and update timestamp schemas?
4. How should a resident select the applicable feed when DTEK returns two schedules for one building?
5. Does YASNO currently intend the Kyiv group schedule to be a separate product/model, and does it claim any relationship to DTEK's new individual-address schedules?
6. What minimum freshness age should the product display as stale, given DTEK's day-ahead and change-at-any-time wording?
7. If no supported DTEK interface exists, should product scope change to an explicitly labeled group schedule, or should live data integration wait?

**Stop condition:** Do not implement a DTEK scraper, browser automation, edge-token flow, or WAF workaround. Resolve the supported-access question before Phase 3B provider code.
