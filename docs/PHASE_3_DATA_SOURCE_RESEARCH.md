# Phase 3 Data Source Research: YASNO Group Schedule

**Research evidence dates:** 2026-11-07 and 2026-11-11 (see [Phase 0 findings](PHASE_0_FINDINGS.md) and the evidence below).

**Current product decision:** YASNO group schedule is the approved primary automatic source for Phase 3. This is a group-level product; it does not claim an address-specific outage schedule.
**Scope:** documentation revision. No new HTTP requests or application changes were made for this revision.

## Decision and semantics

Use YASNO's planned outages endpoint for a user-directly-selected Kyiv group/subgroup. Phase 3 does not resolve addresses, infer groups from addresses, or require an address. Do not invent or hardcode a supposedly complete group list. Prefer deriving selectable identifiers from actual keys in the provider schedule response when its structure supports this; validate the selected provider/group identity against returned data and preserve the exact identifier, including subgroup notation such as `19.1`. The selected identity includes provider and group identifier. The current evidence establishes that the schedule response is group-keyed, but does not establish complete group coverage or a separate safe enumeration endpoint; selector coverage is therefore a technical limitation to resolve from provider response data, never by guessed choices. A group schedule is not individually verified for a building or apartment; the UI must say actual outages there may differ.

DTEK address-specific automatic integration is out of scope for Phase 3 and is not a blocking dependency. Do not investigate, automate, or bypass DTEK edge protection. Historical DTEK findings below remain evidence about the limits of the prior investigation, not Phase 3 work.

## Verified endpoint and response evidence

The 2026-11-11 unauthenticated GET to the following endpoint returned HTTP 200 JSON (28,952 bytes), `Cache-Control: max-age=300, public`, and `Date: Wed, 11 Nov 2026 16:21:34 GMT`:

`https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages`

The Phase 0 sanitized fixtures and the live response extract recorded in the Phase 0 report show a top-level object keyed by group strings (for example `19.1`); each observed group record contains `today`, `tomorrow`, and `updatedOn`. Day objects contain `slots`, `date`, and `status`; observed slot objects contain integer `start`/`end` minute-of-day values and `type`. Observed statuses include `ScheduleApplies` and `WaitingForSchedule`; observed slot types include `Definite` and `NotPlanned`. These statements describe observed payloads, not a published compatibility contract.

The 2026-11-11 response's `updatedOn` value was `2026-11-10T20:00:02Z`. The earlier sanitized fixture recorded for 2026-11-07 has group `19.1`, `today.date` `2026-11-07T00:00:00+02:00`, `tomorrow.status` `WaitingForSchedule` with empty slots, and `updatedOn` `2026-11-07T11:45:01+00:00`. Day dates therefore included an explicit offset in the observed fixture; `updatedOn` was UTC. Interpret `start` and `end` as minutes within the corresponding day only because that is how the observed sample and existing research interpret the values; verify against new fixtures before implementation.

Sanitized payload extracts, headers, and context are preserved in [Phase 0 findings](PHASE_0_FINDINGS.md). No new fixture was created for this documentation-only decision. Reference endpoint links: [planned outages](https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages), [regions](https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/regions).

## Group identity evidence (not a selector catalog)

Phase 0 verified two provider-returned examples through YASNO address suggestions and `/addresses/v2/group`. These are historical evidence only, not an approved address lookup flow or a complete selector catalog:

| Provider-returned sample | Returned group identity |
|---|---|
| `вул. Хрещатик, 1` | `group: 19`, `subgroup: 1` → `19.1` |
| `просп. Бажана, 10` | `group: 37`, `subgroup: 1` → `37.1` |

The researched group endpoint is `GET /api/blackout-service/public/shutdowns/addresses/v2/group` with `regionId`, `dsoId`, `streetId`, and `houseId`; the tested response was `{ "group": 19, "subgroup": 1 }`. This address mapping flow is explicitly out of scope for Phase 3. Its two observations neither justify implementing address resolution nor establish selector coverage.

The schedule endpoint's group-keyed shape is directly evidenced by the live response and fixtures. Region `25` was returned as Kyiv and DSO `902` as DTEK Kyiv Electricity Networks by the regions response. Do not hardcode these identifiers as a durable contract; validate returned region/operator metadata if implementation uses it.

## Freshness and limitations

- `Cache-Control: max-age=300` describes observed intermediary caching, not a publication or freshness guarantee.
- On 2026-11-11, `updatedOn` lagged the HTTP `Date` by about 20 hours. The earlier 2026-11-07 sample lagged by about 8 hours 38 minutes. A successful HTTP response or recent client fetch must not be presented as a recent provider schedule update.
- The observed endpoint includes `updatedOn`; it is the product's source-freshness timestamp, while local successful retrieval time (`fetchedAt`) is stored separately. Never substitute HTTP `Date`, `Cache-Control`, or local fetch time for it. The exact provider contract, update cadence, and uniformity across groups remain undocumented. Product policy, not a YASNO guarantee: age `<= 6 hours` is CURRENT; `> 6 and <= 12 hours` is STALE; `> 12 hours` is STALE with a stronger warning. Missing, malformed, unusable, or future `updatedOn` is never current; a future timestamp is invalid and rejected.
- The earlier probable-outages endpoint is a separate group-keyed weekly response and is not the approved Phase 3 primary source. Do not combine its possible-period semantics with planned outage slots without a separate product decision.
- `WaitingForSchedule` with empty slots was observed for tomorrow. It is not an all-available schedule. Missing groups, missing days, empty slots, unknown status/type values, malformed JSON, and unexpected date/time representations must be treated as unavailable/invalid; never fabricate availability.
- The endpoint was observed unauthenticated, but no published API contract, SLA, quota, rate limit, or compatibility commitment was found in the research.
- The 2026-11-11 live check is point-in-time evidence. Endpoint behavior and response schema may change.

## Failure behavior requirements

Transport failures, timeout/offline conditions, non-2xx status (including rate limiting), invalid JSON/schema, unknown enum values, absent requested group, unsupported day status, invalid slot bounds/order, and stale or implausible timestamps must fail closed. Preserve the last valid snapshot on all such failures. A valid waiting/no-schedule response may update a visible refresh/error state, but must not overwrite the last valid schedule with fabricated intervals. UI must distinguish current group schedule, stale last-known-good group schedule, and unavailable data.

## DTEK status

DTEK's official Kyiv page returned challenge HTML during the documented prior request, not a verified schedule API response. The historical research did not establish a supported machine interface. DTEK address-specific automatic integration is explicitly out of Phase 3 scope; no edge challenge, token flow, browser automation, scraper, or WAF workaround is to be investigated or implemented.

## Sources

- [Phase 0 findings](PHASE_0_FINDINGS.md) — sanitized real YASNO response extracts, address-to-group examples, endpoint observations and limitations.
- [YASNO live regions endpoint](https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/regions).
- [YASNO live planned schedule endpoint](https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages).
- [DTEK Kyiv shutdown page](https://www.dtek-kem.com.ua/ua/shutdowns) — historical source checked, not part of automatic Phase 3 integration.

## Remaining technical uncertainties

1. YASNO publishes no verified compatibility contract, service level, quotas, or rate limits in the research.
2. `updatedOn` semantics/cadence are undocumented; the approved 6/12-hour thresholds are product policy, not provider guarantees.
3. The schedule response is observed to have group keys, but completeness of group coverage and behavior if groups are omitted is unknown. Build choices only from verified provider data and report coverage limitations; never guess missing groups.
4. Behavior for unavailable groups, partial days, DST transitions, empty slots beyond the observed waiting state, and future schema changes requires fixture-backed handling.
5. The actual outage experienced at an individual property can differ from the selected group's displayed schedule; no address-level accuracy is claimed.
