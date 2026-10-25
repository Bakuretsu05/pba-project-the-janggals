# Final targeted recovery and QC — 2026-10-26

This pass investigated only the five requested missing histories, 3C-010 momo,
APPL-003 Coupang and the authorization statement. **No price rows were added,
removed or changed.** The entire 2,867-row CSV remains byte-for-byte identical to
PR commit `fedb6d8`, SHA-256
`b684d8e7ae09294867003c6c67fcce97542452f8acf6b5514d8bbac56a7e46a1`.
The original 1,397-row prefix is also unchanged.

## Exact history recovery

Marvin's `coverage_check_2026-10-22.csv` confirms all four search misses previously
returned HTTP 200, `result: true`, and nonempty history:

| Listing | Exact history ID | Earlier points | Earlier in-window points |
|---|---|---:|---:|
| APPL-020 momo | `tw_pec_momoshop-13903670` | 76 | 35 |
| APPL-020 PChome | `tw_ec_pchome24h-DMBI4K-A900INYCB` | 30 | 9 |
| BEAU-020 PChome | `tw_ec_pchome24h-DDAB4W-A900HAV8C` | 50 | 16 |
| FOOD-002 PChome | `tw_ec_pchome24h-DBAY5B-A900J35DD` | 35 | 3 |

The earlier search failures do **not** establish that those histories are unavailable.
Current exact endpoint access is **untested**. The prior coverage CSV records
counts/extrema, not complete timestamp/price series, so it cannot supply replacement
price rows on its own.

The request documented inside this project is:

```text
POST https://biggo.com.tw/api/v1/spa/product/history
{"history_id":"<exact ID>","days":730}
```

The existing manually authenticated in-app browser is still available. Its exposed
control interface supports UI actions and read-only page inspection, but has no
arbitrary POST/network request method; the page also reports **no WebMCP tools**.
Its asset export capability does not export JSON network responses. The separate
Playwright Chrome profile is not the user's authenticated in-app session.

Consequently **zero direct endpoint requests were attempted** in this pass. No
cookies/tokens were extracted, no request was moved to another browser context,
and the old signed-out collector's blocker was not removed. This is a tooling
limit, not a newly observed refusal by BigGo and not a conclusion that these four
IDs no longer exist. No new query variants, search sweep or all-335 rerun occurred.
A session-bound request-capable browser connection or an account-owner export of
just these response bodies is needed to complete the four recoveries. Tokens or
cookies must not be included. Five-second pacing and restriction stop rules apply.

## Targeted quality checks

Only two known exact-ID BigGo history cards were reopened. The SSD card was already
on the current page; HOME-013 was reached through its saved page, inspecting only
its known product ID. Controlled action starts were paced by the existing 5.2-second
helper. One exact retailer SKU link was inspected, with no retry after denial.
New visible observations are retained in ignored
`raw/2025/targeted_qc_2026-10-26.json`; public findings are in
`targeted_qc_2026-10-26.json`.

### 3C-010 momo: parent/variant scope needs separation

The saved API evidence is for **parent** history ID `tw_pec_momoshop-14533852`:
32 points, including six 2025 changes. Its `multiple_product` metadata explicitly
lists these different histories:

- Blue: `tw_pec_momoshop-14533852-14533852_001`.
- Gray: `tw_pec_momoshop-14533852-14533852_002`.

The exact listing's currently selected gray UI table was checked again. It contains
nine points beginning **2026-04-01 11:00**, with no 2025 observation. This reproduces
the earlier visible result. The parent response's combined-color title does not
establish that its six earlier changes all describe the catalog's Titan Gray model.

A parent-versus-selected-variant comparison is a plausible explanation for the
coverage difference. **This is an inference, not a proven wire-level explanation**:
the browser tool cannot inspect which history ID the UI actually requested. No
conclusion is drawn that BigGo deleted data or that the original parent prices
were fabricated. The six original rows remain intact and explicitly unresolved
for gray-specific analysis. Resolve with the gray child history, or have the team
decide how to treat parent-only history; do not silently relabel or delete records.

### APPL-003 Coupang: mismatch confirmed, no substitute

Saved history `tw_pec_coupang-451592771846147` names **EH-NE57-P pink**. The catalog
asks for **EH-NE57-A blue**. The saved response has no `multiple_product` option list,
and the earlier exact-ID chart review also showed pink. No new request was needed
to establish this mismatch. Its 30 original rows retain their MISMATCH warnings.

**Team decision:** correct the catalog/link mapping or exclude these prices from
blue-specific analysis. A replacement product/link would require an explicit mapping
decision and new matching evidence; pink prices cannot be treated as blue prices.

### HOME-013 Coupang: correct single-bottle SKU remains unconfirmed

Exact parent ID `tw_pec_coupang-301209210552330` still displays a **500mL** title.
The observed menu contains generic `1瓶`, `2瓶`, `3瓶` etc., plus explicitly labeled
750ml multipacks. There is no explicit **750ml x1** label. A generic single-bottle
label is insufficient proof of volume.

The displayed link also identifies item/vendor **305561811779590 / 305559567810571**,
whereas the catalog link specifies **301207012720650 / 301209210552326**. Matching
the parent product ID therefore does not resolve the catalog SKU. A single direct
visit to that exact catalog URL displayed an **access-denied page (`error403`)**;
no retry or bypass was attempted.

**Unresolved:** confirm the catalog's 750ml single-bottle SKU and its matching
history. A successful parent-history response alone would not prove that physical
variant. Keep excluded until confirmed; this does not establish that all possible
representations of its history are unavailable.

## Authorization wording

The earlier direct user message states:

> Yes, the team has explicitly approved authenticated BigGo history collection using my own account.

That supports the audit's statement that the **user explicitly authorized the work
and reported team approval**. No separate team minutes, resolution or another team
member's approval was independently reviewed. The authorization document and audit
now make that attribution explicit. Permission was not inferred from Marvin's prior
signed-in activity or from successful login. No additional approval is being claimed,
and the project specification remains unchanged.

## Disposition

Resolved: the overstatement of four endpoint failures, the authorization attribution,
and the distinction between parent and selected-variant evidence in the SSD review.
The SSD's actual request/variant attribution remains unproven; the mismatch itself
has not been signed off.

Still blocked by tooling: the four exact authenticated history requests.
Still requiring identity evidence/team treatment decisions: HOME-013's SKU,
3C-010's gray-specific history, and APPL-003's pink/blue mapping. The attempted count refers to target processing/search attempts, not 335 exact
endpoint requests. Counts remain 335 targets processed, 330 accepted histories, 327 listings with relevant records and 2,867
rows. The 34-listing review remains qualified with unresolved findings. PR #11
remains draft, targets main and is not merged.

Validation after this pass: **23/23 Node tests and 9/9 Python tests passed**. Both
CSV-only and full raw-to-CSV validation passed. Offline rebuild left the entire
CSV byte-for-byte unchanged; the original prefix hash also remains unchanged.
