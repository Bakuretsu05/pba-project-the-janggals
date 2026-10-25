# 2025 BigGo collection audit — partial, access blocked

Collected by Albert on **2026-10-25, Taiwan time (UTC+8)**.
Repository base: `a748c5c0dc023b6a5a225a16f1043c96bf921e02`.
**Milestone 2 is not complete.** The CSV contains real collected data; it is not a full 335-listing dataset.

## Verified results

| Platform | Targets | Successfully retrieved | With relevant historical records | CSV rows |
|---|---:|---:|---:|---:|
| momo | 150 | 48 | 47 | 410 |
| pchome | 150 | 48 | 48 | 400 |
| coupang | 35 | 20 | 20 | 587 |
| Total | 335 | 116 | 115 | 1397 |

The 116 retrieved listings cover **Electronics and Appliances only**:

| Category | Retrieved listings |
|---|---:|
| Electronics (3C) | 72 |
| Appliances (APPL) | 44 |
| Beauty (BEAU) | 0 |
| Food (FOOD) | 0 |
| Home (HOME) | 0 |

This partial collection cannot support a five-category comparison. The existing
rows are preserved byte-for-byte: SHA-256
`6a888791005a1a6818f01753e5bccfdcdf764446f184fb350a9c14cc08851842`
(224,745 bytes; 1,397 data rows).

“Relevant historical records” means an observed change within Oct 1–Nov 25, 2025,
or the last preceding observed change used as a baseline. It does **not** certify a
complete period, correct physical variant, or continued tracking. Of the 116
retrieved listings, 95 have an actual in-window change. 3C-002 momo has only 2026
history and correctly contributes no row. Six retrieved listings lack a pre-period
baseline (including series first observed on Oct 1). No daily prices were filled.

The **219 outstanding listings** consist of **APPL-019 momo blocked** and **218
not attempted after the global stop**. Every target and its status, original
classification, title and unresolved note is in `collection_status_2025.csv`.

## Exact access blocker

At **2026-10-25 20:50:03.094 Taiwan time**, the signed-out browser request was:

```text
POST https://biggo.com.tw/api/v1/spa/product/history
{"history_id":"tw_pec_momoshop-6198895","days":730}
HTTP 429
{"result":false,"require_login":true}
```

See `access_blocker_2025.json` and ignored raw evidence
`raw/2025/APPL-019_momo_attempt1.json.gz`. The collector stopped immediately;
it did not retry the login restriction, log in, rotate identities, change IPs,
export tokens, or reset a session to continue requests. The blocker file prevents
accidental resumption or repeat collection until the project makes an authorized
scope decision. Normal signed-out access succeeded for 116 unique listings before
this response. The reason the restriction appeared at that point is **unknown**;
a quota, session requirement or other cause is not established.

An ordinary signed-out browser check of this exact listing after the restriction
showed just one flat point ($3300 at 2024-10-25 20:51), whereas Marvin's report had
37 points and three in-window points (NT$2990–3500). This display was not accepted
as reliable historical evidence and no row was invented from it.

Specification section 3 excludes anything behind a login. The user explicitly chose
to **keep the no-login scope and deliver the documented partial dataset**. The login
blocker remains in place. No additional collection was performed during the
reproducibility fix, and the project specification was not changed.

## Access and identity checks

- Initial three-platform signed-out tests all returned HTTP 200 with real series.
- A fresh Playwright Chrome context used the exact NFR-2 study user agent and the
  existing project's configured `SCRAPER_CONTACT`. The address was kept in ignored
  `.Renviron`, not source files, reports, logs or Git.
- `robots.txt` was checked on 2026-10-25: `Allow: /`, `Disallow: /r/`. No redirect
  endpoint was requested. Saved copy: `raw/2025/robots.txt`.
- The public [BigGo terms page](https://biggo.com.tw/official/disclaimers?tag=privacy)
  was reviewed before the full run (page states last update 2026-01-09). It contains
  privacy, disclaimer and cashback terms; no express general collection ban was
  identified in that published page. This check does not authorize login-only data.
- All logged controlled request starts were at least **5.199 seconds**
  apart. No CAPTCHA was encountered. No authenticated browser profile was used.
  The earlier one-history diagnostic did not insert five-second gaps between its
  homepage/robots setup calls. All history-to-history requests and the subsequent
  collector's controlled requests were paced; the setup diagnostic is not in that log.

## Data handling

The original eight-column header and product IDs are retained. Identifiers come
from `products/products.csv`, never the first search result. Coupang uses the
`/products/` number, not `itemId`. Response history ID, shop code, item ID, currency
and product URL are checked; Coupang referral URLs are checked by `pageKey` and
deep-link product ID without following them.

UTC milliseconds are explicitly converted to UTC+8. Only consecutive equal
prices are collapsed. A return to a former price remains a new event. The last
real change before Oct 1 is included, rather than the last repeated observation.
Every change through Nov 25 23:59 Taiwan time is included. If distinct events share
a minute, source milliseconds are placed in `note` to distinguish them. Only 2025
rows and the required baseline are emitted; no 2026 dataset was created. Full
730-day responses are retained as source evidence and to assess tracking continuity.

## Gaps and ambiguities

All original flags remain unresolved unless stated otherwise. They are not changed
into OK simply because the endpoint returned data. Applicable warnings are repeated
in every exported row's `note`; listings with no rows retain issues in the status file.

- **8 SHORT:** 3C-002 momo; 3C-010 momo; 3C-010 pchome; APPL-010 pchome; APPL-020 coupang; FOOD-007 pchome; HOME-009 coupang; HOME-013 coupang.
- **MISMATCH:** APPL-003 Coupang still identifies EH-NE57-P pink; the table asks for
  EH-NE57-A blue. Its 30 real history rows are retained with explicit MISMATCH notes;
  they must not be treated as a verified blue-variant series.
- **13 stopped series:** 3C-004 pchome; APPL-022 pchome; BEAU-002 pchome; BEAU-021 momo; HOME-005 momo; HOME-008 momo; HOME-014 pchome; HOME-015 pchome; HOME-020 pchome; HOME-023 pchome; HOME-024 pchome; HOME-028 momo; HOME-028 pchome. No assumption of constant price through stopped
  tracking is made. Of these, 3C-004 PChome has been retrieved so far.
- **38 UNCERTAIN** in the original 335-listing inventory include the stopped series,
  ambiguous sizes/sets/flavours and 16 Coupang titles missing model/size/pack details.
  Full issue text is retained for all targets in the status file and original coverage
  report. Five UNCERTAIN and one MISMATCH listings have been retrieved so far.

## Validation and independent verification

- `node --test biggo/test_collect_2025.cjs`: **18/18 passed**, covering baseline
  selection, repeated prices, same-minute reversals, inclusive Nov 25 cutoff, UTC+8
  rollover, SHORT, MISMATCH, invalid values/identity, empty/2026-only histories,
  CSV quoting/Chinese and the 335-ID inventory/34-listing sample. Seven new
  regressions cover absent/empty/partial/corrupt/truncated raw evidence, missing
  evidence for a zero-row retrieved listing, and successful evidence-complete rebuilds.
- `python biggo/test_validate_2025.py`: **7/7 passed**, including read-only CSV-only
  validation in a fresh-checkout fixture, clear failure of explicit raw mode without
  evidence, and CSV-only rejection of invalid dates, chronology, duplicates and
  consecutive equal prices.
- `python biggo/validate_2025.py`: **1,397 rows pass CSV-only validation**, which
  does not verify source histories. It works with no gitignored raw directory.
- `python biggo/validate_2025.py --raw`: **all 116 saved responses and 1,397 CSV rows pass**
  independent raw-to-CSV reconstruction, exact schema/order, identifiers, chronology,
  nonnegative integer prices, duplicates, metadata, date window, collection dates and
  UTF-8/Chinese round-trip checks. This mode requires the local raw evidence and
  request log. This validates collected rows, not full coverage. The committed
  `validation_2025.json` is this executed raw-verification report, not a claim that
  a fresh checkout contains its source evidence.
- Rebuilt locally using all saved evidence and compared the CSV to the pre-fix
  snapshot: **byte-for-byte identical**, with the SHA-256 above. Regression fixtures
  also confirm that refusal does not modify the CSV or status file.
- All 116 retrieved series have the same 2025 point counts and min/max values as
  Marvin's earlier coverage report. No discrepancy was found in these summary checks.
- **1 listing independently verified** against BigGo's visible two-year table:
  3C-003 momo, all eight exported records match (`chart_checks_2025.csv`).
- **0 listings re-requested** in the planned repeat audit. The planned sample is
  34 (10 momo, 16 PChome, 8 Coupang), including all 8 SHORT, 13 stopped series,
  the mismatch and examples of OK/other UNCERTAIN. That requirement remains unmet
  because further historical requests stopped on the login restriction.
- `validation_2025.json` explicitly reports `dataset_complete: false` and the
  restriction. `verification_2025.csv` has its header only; it does not claim success.

## Files and reproduction

Modified: `biggo/price_changes.csv`, `biggo/README.md`.
Added: `collect_2025.cjs`, `test_collect_2025.cjs`, `validate_2025.py`, `test_validate_2025.py`,
`collection_status_2025.csv`, `verification_2025.csv`, `chart_checks_2025.csv`,
`validation_2025.json`, `access_blocker_2025.json`, and this audit, all in `biggo/`.
Ignored local evidence is retained in `biggo/raw/2025/`. The ignored `.Renviron`
contains only the reused contact setting. No teammate's unrelated file, product
table or specification was changed. The PR packages the partial dataset and these
reproducibility fixes; raw evidence and contact configuration remain excluded from Git.

Run `python biggo/validate_2025.py` in a clean checkout for CSV-only checks.
Restore the delivered `biggo/raw/2025/` evidence before running
`node biggo/collect_2025.cjs rebuild` or `python biggo/validate_2025.py --raw`.
Rebuild fails before changing outputs when required evidence is absent, invalid or
incomplete. Online collection remains blocked. See README for exact commands.
