# BigGo price history

## Current 2025 delivery (updated 2026-10-28)

The dataset contains **3,908 change-point rows** from **331 listings with relevant
2025 records**. **334 histories are retrieved** across all 335 processed targets:
150 momo, 150 PChome and 34 Coupang. HOME-013 Coupang remains without accepted
2025 rows; its recorded reason is retained and the team requires no further work.

The current study window is **September 1-November 25, 2025**, plus the last real
change before September 1 (spec section 11, updated on main in `3531549`). The
September expansion adds 989 rows from already-saved evidence. One direct request
for each of APPL-020 momo/PChome, BEAU-020 PChome and FOOD-002 PChome then recovered
all four histories (HTTP 200), adding another 52 rows. No search or full collection
rerun was needed. The four new response collection dates are October 28 Taiwan time.

All **2,867 previous price records remain present**, including the original 1,397.
No existing price, timestamp, product/platform link or entry date changed. Window
baseline wording and same-minute event-order notes changed on 153 existing rows.
Inserting September rows means the old bytes are no longer a prefix; preservation
now compares all seven non-note fields and their multiplicities. See
[preservation_2025.json](preservation_2025.json) for hashes and the correction record.

**286 tracking coverage rows** in
[history_coverage.csv](../analysis/config/history_coverage.csv) allow the analysis to
carry unchanged prices through November 25 only for momo/PChome series observed
past that date. None of the 14 stopped series receives a coverage extension. This
includes the 13 known stopped series and FOOD-006 momo. Coverage is not a fabricated
price-change row, and never supplies a price before a listing's first observation.

### Team decisions now recorded in the specification

Spec section 3 explicitly permits signed-in BigGo collection using a team member's
account (`8827ffa`, 2026-10-27). Passwords, cookies and session tokens stay out of Git.
The old HTTP 429 marker is historical evidence of signed-out access; its `action`
now points to the approved signed-in workflow. It is not a scope prohibition.

The team leader's Oct 27 decisions are now in section 11:

- Keep every product and all collected rows, with SHORT/MISMATCH/UNCERTAIN warnings.
  Do not replace products or silently relabel variants.
- Keep the six 3C-010 momo 2025 rows flagged; no further gray-variant work is required.
- Coupang is excluded from the analysis. Its APPL-003 pink/blue, HOME-013 and vague
  title flags require no further collection or product replacement.
- The title-variant listings remain in the data. H1-H4 sensitivity checks will compare
  results with and without BEAU-005 PChome, BEAU-006 momo, BEAU-011 momo, FOOD-003
  PChome, FOOD-009 PChome, FOOD-026 momo/PChome and HOME-016 momo/PChome.
- A series ending before November 25 receives no tracking coverage row.

There are **34 saved independent chart reviews**, accepted by the team leader as
the approximately 10% check. They cover the original October-November window;
September rows were reconstructed from saved full histories, without claiming new
website checks. Review differences and the team's disposition remain documented.
FOOD-002 PChome's recovered parent title offers several flavours; its rows carry
an explicit warning rather than claiming proven original-flavour attribution.

### Reproduce and validate

```sh
python biggo/validate_2025.py
node --test biggo/test_collect_2025.cjs
python biggo/test_validate_2025.py
```

Default validation is read-only and explicitly **CSV-only**; it verifies schema,
identity, chronology, metadata, changes, flags and tracking coverage without raw
files. It does not claim raw reconstruction. Restore `biggo/raw/2025/` from the
separate evidence bundle for full offline verification or rebuild:

```sh
python biggo/validate_2025.py --raw
node biggo/collect_2025.cjs rebuild
```

Missing, incomplete, corrupt or truncated raw evidence cannot delete/change existing
CSV records or withdraw retrieved zero-row statuses. Refusal leaves both outputs
unchanged. The one-time `rebuild --extend-window` migration additionally reconstructs
the old October export from the same evidence before permitting window-dependent
note changes; it still requires every existing price record in the September export.
Ordinary rebuild keeps its strict full-record guard. No migration is required after
restoring the current CSV. Raw verification also checks the status continuation
dates supporting the coverage file. CSV checkout line endings are pinned to LF.

Signed-in UI collection helpers are `collect_visible_2025.cjs` and the loopback-only
`visible_checkpoint_server.cjs`. The legacy fresh signed-out HTTP collector stays
stopped on its historical restriction; it must not be mistaken for the user's
signed-in browser. No browser profile or authentication state is copied. The four
recovered response bodies are saved under their exact product/platform raw filenames;
earlier UI search failures are archived. See [recovery_2026-10-28.json](recovery_2026-10-28.json).

`apply_catalog_variants.cjs` accepts a recognized protected CSV snapshot and checks
record containment instead of an obsolete byte prefix. The team's current decision
is to retain flagged listings, so no further variant substitutions are performed.
[Audit](AUDIT_2025.md) records reviewer feedback, validation and remaining limits.
The older [Oct 26 QC report](TARGETED_QC_2026-10-26.md) is historical and is superseded
by the current specification and the successful Oct 28 exact-ID recovery.

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
