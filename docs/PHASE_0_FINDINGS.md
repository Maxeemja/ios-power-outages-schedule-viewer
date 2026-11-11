# Phase 0 Findings: Kyiv Electricity Data Sources

**Research date:** 2026-11-07 (UTC)

**Scope:** Read-only API/source investigation. No application source code was changed.

**HTTP tests:** Direct `curl` requests with a generic `Mozilla/5.0` user agent. YASNO requests were unauthenticated. DTEK direct access was blocked by its edge challenge in this environment.

## Executive summary

YASNO's live API is reachable and its address resolver works for Kyiv, but the live schedule shape remains group-oriented (`19.1`, `37.1`, etc.). DTEK's current official Kyiv page says schedules are now calculated per address and the former queue model no longer applies. Therefore, YASNO is not a verified match for the current DTEK individual-house schedule model, even though it still resolves addresses to groups and publishes daily group schedules.

DTEK is the authoritative source and appears to expose an underlying WordPress AJAX lookup flow according to a community reverse-engineered client. However, the current official site could not be fetched directly: the response was an Imperva/Incapsula challenge page, so its current AJAX calls and response schema could not be verified live. No provider is ready for implementation. A backend adapter is **not yet proven sufficient or necessary**: it would not make an inaccessible or unapproved upstream interface reliable, and the app must not bypass the DTEK WAF.

## 1. Verified endpoints and HTTP status

| Source / endpoint | Result on 2026-11-07 | Notes |
|---|---:|---|
| `GET https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/regions` | `200` | JSON listed region `id: 25`, `value: "Київ"`, DSO `id: 902`, `name: "ТОВ «ДТЕК КИЇВСЬКІ ЕЛЕКТРОМЕРЕЖІ»"`. Confirms these IDs currently name Kyiv City Networks. |
| `GET https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages` | `200` | JSON schedule map, response `Cache-Control: max-age=300, public`, `Date: 2026-11-07T20:22:54Z`. See sanitized fixture below. |
| `GET https://app.yasno.ua/api/blackout-service/public/shutdowns/probable-outages?regionId=25&dsoId=902` | `200` | JSON weekly probable schedule, response `Cache-Control: max-age=300, public`, `Date: 2026-11-07T20:23:31Z`. |
| YASNO address `GET .../addresses/v2/cities?regionId=25&dsoId=902&query=Київ` | `200` | Empty list. A city selection is not required for Kyiv street lookup in the tested flow. |
| YASNO address `GET .../addresses/v2/streets?regionId=25&dsoId=902&query=Хрещатик` | `200` | Returned `[{"id":915,"value":"вул. Хрещатик"}]`. Address suggestion cache was `private,max-age=120`. |
| YASNO address `GET .../addresses/v2/houses?regionId=25&dsoId=902&streetId=915&query=1` | `200` | Included provider-returned house `{"id":41259,"value":"1"}` and other matches. |
| YASNO address `GET .../addresses/v2/group?regionId=25&dsoId=902&streetId=915&houseId=41259` | `200` | Returned `{"group":19,"subgroup":1}`. |
| YASNO address `GET .../addresses/v2/streets?regionId=25&dsoId=902&query=Перемоги` | `200` | Returned `вул. Перемоги` (id 641) and `сел. Перемоги` (id 1234); the same string is ambiguous without narrowing to an exact provider item. |
| YASNO address `GET .../addresses/v2/houses?regionId=25&dsoId=902&streetId=641&query=1` | `200` | Included provider-returned house `1` (id 27896). |
| YASNO address `GET .../addresses/v2/group?...&houseId=27896` | Not run | This house was not used as the second confirmed address. The second address used below is from a different Kyiv area. |
| YASNO address `GET .../addresses/v2/streets?regionId=25&dsoId=902&query=НЕТАКОВАНА` | `200` | Returned `[]`. This is an unmatched search string, not a claimed real street or test address. |
| YASNO address `GET .../addresses/v2/group?...&houseId=99999999` | `404` | Synthetic invalid internal house ID (not a residential address); body code `EntryNotFound`. Not counted as a real-address test. |
| `GET https://www.dtek-kem.com.ua/ua/shutdowns` | `200` | Body was a 212-byte Incapsula challenge/bootstrap HTML with `robots noindex,nofollow`, not the site page or its frontend scripts. No current network requests could be extracted. |

The live DTEK site was separately readable through indexed page content, which exposes the current public text but does not expose its active network trace. That page says to search in Ukrainian Cyrillic, select a street, then a house number. It also says the schedule is unique to each address and warns that some multi-feed buildings can have different schedules per apartment. This confirms the current product model, but does not verify an API endpoint.

### Sanitized real-response fixtures

These are deliberately small extracts of actual YASNO HTTP response bodies. Cookie values, request IDs, correlation IDs, and unrelated residential addresses are omitted. The schedule fixture is a subset of the real response for group `19.1`; it does not synthesize schedule fields.

**Regions response extract**

```json
[
  {
    "hasCities": false,
    "dsos": [
      { "id": 902, "name": "ТОВ «ДТЕК КИЇВСЬКІ ЕЛЕКТРОМЕРЕЖІ»" }
    ],
    "id": 25,
    "value": "Київ"
  }
]
```

**Address flow response extracts (each block is the exact shape returned by that endpoint)**

```json
[{ "id": 915, "value": "вул. Хрещатик" }]
```

```json
[{ "id": 41259, "value": "1" }]
```

```json
{ "group": 19, "subgroup": 1 }
```

**Planned schedule response extract**

```json
{
  "19.1": {
    "today": {
      "slots": [
        { "start": 0, "end": 420, "type": "Definite" },
        { "start": 420, "end": 570, "type": "NotPlanned" },
        { "start": 570, "end": 1110, "type": "Definite" },
        { "start": 1110, "end": 1200, "type": "NotPlanned" },
        { "start": 1200, "end": 1440, "type": "Definite" }
      ],
      "date": "2026-11-07T00:00:00+02:00",
      "status": "ScheduleApplies"
    },
    "tomorrow": {
      "slots": [],
      "date": "2026-11-08T00:00:00+02:00",
      "status": "WaitingForSchedule"
    },
    "updatedOn": "2026-11-07T11:45:01+00:00"
  }
}
```

**Probable schedule response extract**

```json
{
  "25": {
    "dsos": {
      "902": {
        "groups": {
          "19.1": {
            "slots": {
              "0": [{ "start": 0, "end": 1440, "type": "NotPlanned" }],
              "1": [{ "start": 0, "end": 1440, "type": "NotPlanned" }],
              "2": [{ "start": 0, "end": 1440, "type": "NotPlanned" }],
              "3": [{ "start": 0, "end": 1440, "type": "NotPlanned" }],
              "4": [{ "start": 0, "end": 1440, "type": "NotPlanned" }],
              "5": [{ "start": 0, "end": 1440, "type": "NotPlanned" }],
              "6": [{ "start": 0, "end": 1440, "type": "NotPlanned" }]
            }
          }
        }
      }
    }
  }
}
```

The probable response has no returned per-record timestamp in the inspected schema. In this live sample, all weekday slots for `19.1` were `NotPlanned`, while the current planned endpoint contained several `Definite` periods on the same date. Treat these as distinct schedule products, not interchangeable encodings.

**Not found behavior**

The synthetic invalid house ID test returned an HTTP `404` problem response with `title: "EntryNotFoundException"`, `status: 404`, and `code: "EntryNotFound"`. This verifies the not-found signaling only; it does not establish that an actual residential address is absent.

## 2. Address-to-schedule resolution

### YASNO (live verified)

The sequence is:

1. Fetch `/addresses/v2/regions` and select the current region/DSO pair by returned names, not hardcoded IDs alone.
2. Search `/addresses/v2/streets` using `regionId`, `dsoId`, and a text `query`; narrow/confirm the exact returned street item. `Хрещатик` resolved to `вул. Хрещатик`.
3. Search `/addresses/v2/houses` using the returned `streetId` and a house-number `query`; select the exact returned house item. On that street, query `1` returned house `1` and multiple other houses beginning with `1`.
4. Request `/addresses/v2/group` with the returned `streetId` and `houseId`. It returned `group: 19`, `subgroup: 1` for `вул. Хрещатик, 1`.
5. Fetch schedule data by group from `/regions/25/dsos/902/planned-outages`.

For a second, geographically distinct Kyiv sample, YASNO returned `просп. Бажана` (street id `1804`); house query `1` returned house `10` (id `48686`) among its matches, and group resolution returned `37.1`. Therefore the observed examples are:

| Provider-returned address | Resolution |
|---|---|
| `вул. Хрещатик, 1` | `19.1` |
| `просп. Бажана, 10` | `37.1` |

These are provider-resolved samples, not addresses invented for this report. YASNO group lookup returned one `group` and one `subgroup` per tested house. A combined house suggestion such as `10,12` resolved to one group (`20.1`) in this sample; that does not mean it can represent separate apartment feeds.

### DTEK (current flow partially verified)

The official page currently presents street selection followed by house-number selection and says the returned schedule is address-specific. It explains that a building with two or more supply sources may have different schedule graphs for different apartments, and says it cannot currently predict which feed supplies a given apartment. The page itself is authoritative for this current product behavior.

The community client describes an AJAX sequence of page load → discover an AJAX URL → POST `getStreets` → POST `getHomeNum` → use returned house mapping and `preset`/`fact` schedules. This is supporting reverse-engineered documentation only. The DTEK response received during this investigation was a WAF challenge, so this request flow, field names, and any current JSON endpoint have **not** been live-verified against the current site.

### Critical scenarios

1. **Valid Kyiv address 1:** YASNO provider suggestions for `вул. Хрещатик, 1` resolved to group `19.1` (live verified).
2. **Valid Kyiv address 2, different area:** YASNO provider suggestions for `просп. Бажана, 10` resolved to `37.1` (live verified).
3. **Multiple schedule results:** No real address producing multiple YASNO schedule records was observed. YASNO's tested house resolver returns one group/subgroup object. DTEK's official page documents two graphs for some multi-feed addresses, but those results could not be retrieved because of the WAF response. This scenario remains unverified at the API level.
4. **Not found:** An unmatched street query returned `[]`, and a synthetic invalid provider house ID returned `404 EntryNotFound`. No actual residential address was invented or asserted to be absent. A real-address not-found case remains untested.

## 3. Current Kyiv schedule model

The current official DTEK Kyiv page says old queues are no longer active; each address/building receives an individual schedule according to its grid connection. Neighboring buildings can differ. Some buildings have multiple power feeds and may show two schedules, with the applicable one varying by apartment.

YASNO's live schedule endpoint is structurally **group-based**, keyed by strings such as `19.1`; its address endpoint maps a house to one numeric group/subgroup. This data model does not express the documented DTEK per-address/per-apartment model. The live planned schedule describes `today` and `tomorrow`, using minute offsets in slots and statuses such as `ScheduleApplies` and `WaitingForSchedule`. Slot types observed were `Definite` and `NotPlanned`.

The separate probable-outages endpoint returns a group-keyed week of possible intervals, with weekday indices `"0"` through `"6"` and slot types. In the sample, it reported no probable outage for any weekday for group `19.1`, in contrast to definite periods in the planned day schedule. Do not collapse these two endpoint semantics.

## 4. Freshness and update semantics

- Planned and probable schedule responses carried `Cache-Control: max-age=300, public` and matching five-minute `Expires` values.
- Address lookup responses carried `Cache-Control: private,max-age=120`.
- Planned schedule records carried `updatedOn: "2026-11-07T11:45:01+00:00"`; the HTTP `Date` was `20:22:54Z`, so this observed schedule timestamp was about 8 hours 38 minutes older than the response.
- Day records carried explicit timezone offsets (`+02:00`) and dates, while `updatedOn` used UTC. Dates in the sample were current day and next day; tomorrow had `WaitingForSchedule` and an empty `slots` array.
- Probable schedule sample had no update timestamp in the response shape inspected.
- Cache headers show what intermediaries may cache; they are not a guarantee of source publication cadence. The observed stale `updatedOn` warns against treating HTTP 200 as freshness.
- The community Home Assistant integration says it polls the schedule every 15 minutes. That is the integration's behavior, not evidence of an official YASNO rate or refresh contract.

## 5. Authentication, CORS, rate limits, WAF, and reliability

### YASNO

- All tested region, schedule, probable, and address GET requests succeeded without a bearer token, API key, or preexisting session cookie. The edge returned Imperva cookies after the request, but did not require them for these successful initial GETs. This verifies unauthenticated GET access at the time of testing, not a published support commitment.
- The responses did not include `Access-Control-Allow-Origin` in the captured headers. CORS governs browser JavaScript; it does not prevent native iOS `URLSession` requests. A future web client would need separate CORS verification.
- No rate-limit headers or documented quota were found in these responses. Rate limits were not stress-tested. Avoid inferring unlimited usage.
- Schedule endpoints were served through an Imperva CDN and advertised five-minute public caching. Address suggestions advertised two-minute private caching.
- The API is undocumented in the supplied project materials and has no SLA established by this investigation. Schemas, IDs, query behavior, and access policy can change.
- Current YASNO house-to-group resolution is useful for cross-checking a traditional group schedule, but no evidence shows that it now supplies DTEK Kyiv's individual house schedule.

### DTEK

- A direct unauthenticated GET to the official page returned HTTP `200` but only a 212-byte Incapsula bootstrap/challenge HTML body. This is not a usable page or API response.
- The official page is known to display street then building lookup from indexed page content, but no current frontend JavaScript or network requests were obtainable from the direct response.
- The community client explicitly describes WordPress AJAX and Incapsula/Imperva WAF challenges; its documented WAF-clearing technique uses browser automation. That code is not a production guarantee and is not an acceptable app integration path.
- The official page itself warns that high concurrent demand can delay its responses and advises retrying later (up to five minutes). It also says schedules cover only the next day and may change at any time.
- No direct DTEK JSON endpoint, rate limits, authentication requirements for successful AJAX calls, CORS policy, or current endpoint schema could be verified.
- Do not embed browser automation or implement WAF bypass in the iOS app. A backend proxy would still need a legitimate stable upstream access path and permission; placing a WAF bypass on a server would not remove the reliability or policy issue.

## 6. YASNO vs DTEK

| Criterion | YASNO | Official DTEK Kyiv |
|---|---|---|
| Authority for current Kyiv house-specific schedule | Not established for this model; its current payloads are group-based | Authoritative operator source |
| Live reachability in this investigation | Yes; all three schedule/region endpoints and address lookup tested successfully | No; direct request received WAF challenge HTML |
| Address resolution | Live verified street → house → one group/subgroup | Official UI describes street → house; actual current AJAX not verified |
| Schedule model | Group-keyed planned schedule for today/tomorrow plus separate probable week | Official page says individual schedule for each address; possible multiple feeds per address/building |
| Freshness metadata | `updatedOn` on planned schedule; absent in probable sample | Current exact metadata/fields unknown; official page says next-day schedule can change any time |
| Direct iOS feasibility | Technically reachable without browser CORS, but semantic mismatch and undocumented API risk | Not verified; WAF prevents reliable unauthenticated automated fetch in this test |
| Recommendation | Useful comparison/fallback research source only; not a primary for the current schedule model | Desired source if DTEK provides a supported, stable machine interface |

## 7. Recommendation

**Do not choose YASNO as the primary provider for the MVP as currently specified.** Its live group-based API resolves addresses, but that conflicts with DTEK's current individual-house schedule model. A mapping such as `19.1` must not be presented as the current individual schedule for a house without an authoritative confirmation that these represent equivalent current schedules.

**DTEK is the semantically correct source, but its machine interface remains unverified and presently inaccessible to direct automated requests from this environment.** Before implementation, obtain confirmation of a supported public endpoint/feed or find an approved integration path that does not bypass WAF controls. The community AJAX client can guide a later authorized investigation but is not proof that the interface is stable or supported.

## 8. Is a backend adapter necessary?

**Not established.** Native iOS can call the tested YASNO GET endpoints directly, and CORS does not apply to `URLSession`; however, this does not fix YASNO's mismatch with the current per-address DTEK model.

A small backend adapter could normalize and cache DTEK data if DTEK offers a supported server-accessible endpoint or provides an approved feed. It cannot be recommended as a solution to an upstream WAF challenge by itself. Do not build it until a lawful, stable, current source path is demonstrated. If DTEK has no such path, the MVP needs a product/data-source decision before implementation.

## 9. Unresolved questions

1. Does DTEK publish or authorize a stable machine-readable endpoint/feed for individual Kyiv address schedules?
2. What are the current DTEK street, house, schedule, and multi-feed response schemas, and how are apartment-specific choices represented?
3. Does YASNO intend its `regionId=25` / `dsoId=902` schedules to remain as a separate group schedule during the new individual DTEK schedule period, or are these records stale/otherwise distinct?
4. Why did the planned API's `updatedOn` lag the HTTP response by more than eight hours in this sample, and what update cadence is intended?
5. What are YASNO's documented usage terms, rate limits, and compatibility commitments for these public endpoints?
6. Can a real multi-feed DTEK address produce multiple results, and what official process lets a resident determine the apartment's feed?
7. What is the correct way to test a real address-not-found scenario without fabricating a residential address?

## 10. Sources

- [Official DTEK Kyiv shutdown page](https://www.dtek-kem.com.ua/ua/shutdowns) — authoritative current page text; direct HTTP body was WAF challenge HTML during testing.
- [ALERTua/ha-svitlo-yeah](https://github.com/ALERTua/ha-svitlo-yeah) and its [YASNO API client](https://github.com/ALERTua/ha-svitlo-yeah/blob/main/custom_components/svitlo_yeah/api/yasno.py) — reference implementation supporting endpoint and parsing interpretation; live requests above independently verify the tested endpoints.
- [shed-crypto/dtek-blackout-client](https://github.com/shed-crypto/dtek-blackout-client) — reverse-engineered protocol reference only; not treated as proof that the endpoints currently work.
- [Ukrainian News Agency report](https://ukranews.com/en/news/1180673-power-outages-in-kyiv-will-follow-separate-schedule-for-each-address) — recent report of DTEK's individual schedule model.
