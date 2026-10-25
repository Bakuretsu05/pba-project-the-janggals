# BigGo price history

## Current 2025 deliverable

All **335 listings were attempted**. The dataset contains **2,867 rows from 327
listings with relevant 2025 records**; 330 exact listing histories were accepted.
Five listings remain without usable evidence, so Milestone 2 is **not complete**.
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
extended coverage to all five categories under the user's explicit team approval
in [collection_authorization_2025.md](collection_authorization_2025.md). The project
specification is unchanged. The original HTTP 429 `require_login: true` blocker is
retained; the fresh signed-out HTTP collector remains disabled by that marker.

The **34-listing visible-chart review** found 25 exact matches, six catalog pack
corrections, one moving-window baseline qualification, one unresolved SSD history
discrepancy, and one unavailable catalog variant. This is **not 34 clean matches**.
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

## Prior coverage investigation (2026-10-22, Marvin)

The original inventory and identity/coverage warnings remain unchanged in
[coverage_check_2026-10-22.csv](coverage_check_2026-10-22.csv). Product-table BigGo
URLs are searches, not listing identities. Use the shop code plus the platform
product ID from `products/products.csv`; Coupang uses `/products/`, not `itemId`.
The first search result can be a different product.

The earlier coverage inventory classified eight SHORT, one MISMATCH and 38
UNCERTAIN listings. These remain flags, not resolved verdicts. APPL-003 Coupang
still identifies the pink hair dryer while the catalog requests blue. Stopped
series cannot establish a constant price through the rest of the window. The
current browser histories differ from 21 earlier point-count/extrema summaries;
those differences are explicitly retained for review, even after pack corrections.

BigGo history supplies observed timestamp/price points, not original crossed-out
prices. Its two-year availability window moves with the collection date. An
initial flat observation at the window boundary may not be the real change time;
those baselines are marked accordingly. Do not fill missing daily prices or infer
tracking continuity from silence.

The original run checked robots.txt (`Allow: /`, `Disallow: /r/`) and the public
terms page. Redirect links were read for identity without following `/r/`. The
original source investigation used signed-in access; spec section 3's restriction
was later addressed by the user's explicit team exception, without editing the spec.
