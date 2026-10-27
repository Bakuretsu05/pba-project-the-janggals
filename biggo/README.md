# BigGo price history

## Current 2025 deliverable

All **335 target listings were processed** (including UI search attempts, not
335 exact endpoint requests). The dataset contains **2,867 rows from 327
listings with relevant 2025 records**; 330 exact listing histories were accepted.
Five listings remain without accepted collected evidence, so Milestone 2 is **not complete**.
All original 1,397 rows remain a byte-for-byte unchanged prefix of the CSV.

| Category | Accepted histories |
|---|---:|
| Electronics (3C) | 72 |
| Appliances (APPL) | 67 |
| Beauty (BEAU) | 63 |
| Food (FOOD) | 66 |
| Home (HOME) | 62 |

The original partial collection covered only Electronics (72) and Appliances (44),
with zero retrieved Beauty, Food or Home listings. The later authenticated run
extended coverage to all five categories under the user's explicit authorization and reported team approval
in [collection_authorization_2025.md](collection_authorization_2025.md). The project
specification is unchanged. The original HTTP 429 `require_login: true` blocker is
retained; the fresh signed-out HTTP collector remains disabled by that marker.

The **34-listing visible-chart review** found 25 exact matches, six catalog pack
corrections, one moving-window baseline qualification, one unresolved SSD history
discrepancy, and one unconfirmed catalog variant. This is **not 34 clean matches**.
Independent verification still has unresolved findings. See [AUDIT_2025.md](AUDIT_2025.md)
and [chart_checks_2025.csv](chart_checks_2025.csv).

### Validate a fresh checkout

From the repository root, with Python's standard library and Node.js:

```sh
python biggo/validate_2025.py
node --test biggo/test_collect_2025.cjs
python biggo/test_validate_2025.py
```

Default validation is read-only. It reports `validation_mode: csv_only` and
`raw_to_csv_verified: false`, checking schema, identifiers, dates, chronology,
price changes, duplicates, metadata, UTF-8 and status inventory. Saved chart counts
and unresolved findings are reported; no new website checks are performed.
Source completeness, source timestamp conversion, collection dates and pacing
require local raw evidence. CSV line endings are pinned to LF for stable checkout bytes.

### Verify evidence or rebuild offline

Raw evidence is gitignored. Restore `biggo/raw/2025/` from the delivered evidence
bundle first; a Git checkout alone does not include it.

```sh
python biggo/validate_2025.py --raw
node biggo/collect_2025.cjs rebuild
```

Raw mode explicitly requires evidence for every accepted history and the request
log. It independently reconstructs every exported timestamp/price. Missing raw
files cause a clear failure, with no CSV-only fallback. `--output <path>` explicitly
saves a report; the default only prints one. `validation_2025.json` records the
executed full-evidence check, including source types and unresolved coverage.

Rebuild refuses before writing either CSV or status when absent, incomplete,
corrupt or truncated evidence would remove/change existing records. This includes
retrieved histories contributing zero rows. A populated CSV cannot silently become
header-only. Rebuilding the final evidence reproduces the final CSV byte-for-byte.

### Authorized browser continuation

The user manually logged into the in-app browser. Collection used ordinary search
cards selected by exact platform product ID and visible two-year history tables;
no credentials, cookies, JWTs or session tokens were exported. The failed separate
Chrome login was not used. Browser identity remained ordinary; the configured team
contact was reused by the earlier dedicated signed-out collector, but the in-app
browser did not expose a custom user-agent setting. Contact configuration stays in
ignored `.Renviron` and out of Git/evidence bundles.

`collect_visible_2025.cjs` contains the browser collection factory and pacing;
`visible_checkpoint_server.cjs` supplies a loopback-only form for saving public
product evidence incrementally. It requires an already manually authenticated
browser automation tab; it does not create or automate login. Start the local
server with `node biggo/visible_checkpoint_server.cjs`, bind the signed-in tab and
`http://127.0.0.1:8766/` in the browser REPL, and use the factory. `/retry` provides
focused exact-ID searches and `/audit` prioritizes summary differences and known
ambiguities. Controlled BigGo actions use at least 5.2 seconds between starts.

Before accepting a selectable option, inspect its title and the catalog model,
size, pack count and color, then supply its exact `catalog_variant` label. The
factory stops if that choice is missing or unavailable. A listing ID alone does
not identify its physical variant. The table must finish updating after selection.
One focused retry was used for missing IDs; no replacement listing was substituted.

`apply_catalog_variants.cjs <original-1397-row-CSV>` applies explicit, archived
corrections to newly collected listings only. It requires the exact protected
snapshot hash and refuses to alter any listing represented in the original rows. Ordinary rebuild cannot
perform deletions/corrections. `variant_corrections_2025.json` documents every
correction, including the final exclusion of HOME-013 Coupang. Earlier wrong-option
evidence remains in the local bundle. `summarize_chart_checks_2025.cjs` reconstructs
the chart-review report from saved review evidence; it performs no new browser checks.

The original eight-column schema is retained. UTC-millisecond API histories and
Taiwan-minute visible histories are distinguished in provenance. Only consecutive
equal prices are removed; reversals remain. Only Oct 1–Nov 25, 2025 and the last
observed preceding change enter the CSV. Full two-year tables include other years
solely as source evidence. No 2026 dataset has been created.


Owner: **Albert** · 2025 history due **Sun Oct 25** (Milestone 2) · 2026 history due **Sun Nov 29**

## The task

Fill **`biggo/price_changes.csv`** (this folder) with the price history of every product on every
platform it has a BigGo link for, in the format of section 11 of
[`scrapers/data-collection-spec.md`](../scrapers/data-collection-spec.md). The file is already here
with its header line. How the rows are collected is up to Albert: by hand, a script, or browser
automation.

- One row per **price change**. Sep 1 to Nov 25, in 2025 and in 2026, plus the last change before
  Sep 1 so the first day's price is known.
- Also fill `analysis/config/history_coverage.csv` (spec section 11). What makes the history
  accepted is in spec section 13.
- `entered_by` is `Albert`; `entered_on` is the day the row was collected.
- Collect about 10% of listings a second time, or check them against BigGo's chart, and note any
  differences in `note`.
- Scripts that fill the file go in this folder.

## What BigGo's history contains (checked 2026-10-22, Marvin)

Looked at on one momo and one PChome product.

- **No 原價.** BigGo's history gives a timestamp and a price per point, nothing else (answers the
  first half of spec Q4). The crossed-out price only comes from our own daily snapshots.
- **The window is at most 2 years back from today** (the page offers 90 days, 180 days, 1 year,
  2 years; the series starts on the day 2 years ago). Oct to Nov 2025 stays inside it until
  about Oct 2027.
- **Point spacing varies.** One momo series had a point about every day even when the price did
  not change; many others have only a few points over two years, and 77 of 335 listings have no
  point between Oct 1 and Nov 25, 2025 (coverage check below). A missing stretch most likely means
  "price unchanged", but 13 series end before Nov 25, 2025, so check that a series continues past
  a gap before carrying the last price forward. The spec wants change points only, so drop a
  point whose price equals the one before it.
- Timestamps in the response are UTC, in milliseconds. The spec's `changed_at` is Taiwan time
  (UTC+8).
- The same product can flip between two prices several times a day (3C-003 on momo went
  490 / 590 / 490 / 590 on consecutive days in Aug 2026). Keep every change as BigGo shows it;
  the analysis decides what to do with it.

## `biggo_url_*` in the product table is a search page, not a listing

`products/products.csv` links to a BigGo **search** (`biggo.com.tw/s/<query>/?m=cp&c[]=<shop>`).
That page can show several listings: for 3C-003 on momo it showed three, and the first result was
a different item (id `14562513`) from the product in `momo_url` (`i_code=8697108`). Reading the
history off the first result would give the wrong product.

BigGo's history is looked up by an id that is the shop code plus the platform's own item id, the
id the scrapers already extract from `momo_url` and `pchome_url`:

| Platform | Shop code | Item id | Example `history_id` |
|---|---|---|---|
| momo | `tw_pec_momoshop` | `i_code` | `tw_pec_momoshop-8697108` |
| PChome | `tw_ec_pchome24h` | the id after `/prod/` | `tw_ec_pchome24h-DYAJD2-A900GAFRM` |
| Coupang | `tw_pec_coupang` | the number after `/products/` in `coupang_url`, **not** the `itemId` | `tw_pec_coupang-499436216041482` |

With the `itemId` the call returns status 200 but an empty series (all 33 tried). 3C-026 and
3C-028 have no `itemId=` in their link but do have the `/products/` number.

The history view on the page calls `POST https://biggo.com.tw/api/v1/spa/product/history` with
`{"history_id": "<id>", "days": 730}`, and the reply holds `current_price`, `title`, `purl` and
`price_history`, a list of `{x: timestamp, y: price}` points. Both examples above returned a
series; only the title of the momo one was compared with the product.

This is the page's own request, not a documented API. It can change without notice.

**It needs a session token from biggo.com.tw.** A plain HTTP request was refused with 429
`{"result":false,"require_login":true}`. The coverage check made the calls with `fetch()` inside a
Chrome tab on biggo.com.tw, one call every 5.2 seconds, and all 335 returned 200. That Chrome was
Marvin's, signed in to BigGo; whether a signed-out browser gets the same data is untested. The
token expired after about 35 minutes (401 "Jwt is expired"); reloading biggo.com.tw fixed it, so
a long run has to reload the page now and then.

## Known gaps (coverage check, 2026-10-22)

A subagent looked up all 335 listings by ID (150 momo, 150 PChome, 35 Coupang). Full table:
[`coverage_check_2026-10-22.csv`](coverage_check_2026-10-22.csv), with a class and a note per
listing. Every listing returned a series except Coupang under the wrong id format (above). Titles
were matched to the product table by hand and by a digit check, so treat MISMATCH and UNCERTAIN
as flags to look at, not verdicts.

| Class | momo | PChome | Coupang |
|---|---:|---:|---:|
| OK | 140 | 133 | 15 |
| SHORT | 2 | 3 | 3 |
| MISMATCH | 0 | 0 | 1 |
| UNCERTAIN | 8 | 14 | 16 |

- **SHORT** (series starts after Oct 1, 2025, so the price before the period is unknown):
  3C-002 momo (2 points, first on 2026-10-14: no 2025 history at all), 3C-010 momo (2025-10-19),
  3C-010 PChome (2025-10-03), APPL-010 PChome (2025-10-30), FOOD-007 PChome (2025-10-13),
  APPL-020 Coupang (2025-10-03), HOME-009 Coupang (2025-10-04), HOME-013 Coupang (2025-10-06).
- **MISMATCH:** APPL-003 Coupang. The title says EH-NE57-P (pink); the product table says
  EH-NE57-A (blue).
- **UNCERTAIN, series ends before 2025-11-25** (13), so "price unchanged" cannot be told from
  "tracking stopped": momo BEAU-021, HOME-005, HOME-008, HOME-028; PChome 3C-004, APPL-022,
  BEAU-002, HOME-014, HOME-015, HOME-020, HOME-023, HOME-024, HOME-028.
- **UNCERTAIN, variant in the title** (9): BEAU-005 PChome (international air version, 2799
  against momo's 6072), BEAU-006 momo (anniversary limited set), BEAU-011 momo (momo-only set),
  FOOD-009 PChome (covers Coca-Cola and Sprite), FOOD-026 on both platforms (title says 超越仙境,
  the table says "Ultra white"), HOME-016 on both platforms (shampoo and conditioner), FOOD-003
  PChome (flavour and size missing from the title).
- **UNCERTAIN, Coupang titles without a model, size or pack count** (16): see the `note` column.

Spec 6.4 says every product needs BigGo history back to October 2025. Decided 2026-10-27: no
SHORT, MISMATCH or UNCERTAIN product is replaced or dropped (spec section 11, "Flagged listings").

## Conduct

- `robots.txt` checked 2026-10-22: it allows everything except paths under `/r/`.
- BigGo's terms of use were not read (team decision, 2026-10-22).
- Follow the scrapers' pace and identity rules (spec NFR-1 and NFR-2): 5 seconds between requests,
  and the team's contact in the user agent. 335 listings at that pace is about 30 minutes.
- Spec section 3 allows reading BigGo's history while signed in to a team member's BigGo account
  (team decision, 2026-10-27); signed out, the history call gets 429 `require_login`. Passwords,
  cookies and session tokens stay out of the repo. No personal data is collected.
