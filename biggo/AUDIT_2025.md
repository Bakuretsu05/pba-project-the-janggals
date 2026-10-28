# BigGo 2025 audit — reviewer fixes, 2026-10-28

## Current results

The current specification on main (`3531549`) requires **September 1-November 25,
2025**, plus the latest real change before September 1. All 335 inventory targets
were processed; **334 histories were retrieved**, and **331 contribute 3,908 rows**.

| Platform | Targets | Retrieved histories | Relevant histories | CSV rows |
|---|---:|---:|---:|---:|
| momo | 150 | 150 | 149 | 1270 |
| PChome | 150 | 150 | 150 | 1144 |
| Coupang | 35 | 34 | 32 | 1494 |
| Total | 335 | 334 | 331 | 3908 |

HOME-013 Coupang has no accepted 2025 rows; its reason and product are retained.
Three retrieved histories have only later observations and contribute no 2025 row:
3C-002 momo, FOOD-004 Coupang and HOME-009 Coupang. Fifteen retrieved histories
lack a pre-September baseline, and 14 series stop before November 25. These are
source limits; no daily prices, replacement products or baselines were fabricated.

## Reviewer feedback and fixes

All three conversation comments by the team leader were read, including the later
corrections and decisions:

- [6445197409](https://github.com/Bakuretsu05/pba-project-the-janggals/pull/11#issuecomment-6445197409):
  README conflict/deleted collection notes; stale signed-in scope claims; missing
  analysis coverage; flags and four histories needing direct lookup.
- [6446252989](https://github.com/Bakuretsu05/pba-project-the-janggals/pull/11#issuecomment-6446252989):
  retain all products/rows and warnings, no coverage for stopped series, no further
  3C-010 momo or Coupang variant work, and one direct attempt for each missing ID.
- [6446598452](https://github.com/Bakuretsu05/pba-project-the-janggals/pull/11#issuecomment-6446598452):
  merge main, start September 1, populate coverage, recover exact IDs and run the R build.

There were **no inline review comments, formal review submissions, unresolved
review threads or failed checks** at inspection. No feedback was inferred from the
older audit. The entire current PR diff was checked against main, including data
reconstruction and integration with the analysis added by #12/#13.

### Main and collection guidance

Merged main and resolved the README conflict by taking main's collection notes and
placing the new delivery sections above them. The task, shop-code/history-ID table,
request endpoint/body, token-expiry note, 10% review rule and Conduct section remain.
Section 3 now explicitly permits signed-in BigGo history (team decision 2026-10-27,
`8827ffa`). README, authorization documentation and the historical blocker's action
were updated. No formal scope change is inferred solely from account permission.
The prior Oct 26 report is marked historical/superseded rather than current policy.

### September rebuild and preservation

Rebuilt from the already-saved full histories, adding **989 September/baseline
rows** with no new collection. The generator and independent validator now use
September 1. Comparisons with Marvin's Oct 22 summary still use **October 1**, the
window that summary actually measured, avoiding false discrepancy flags.

All **2,867 previous price records** remain, including all original 1,397. No
existing price, timestamp, product/platform link, author or entry date changed.
**153 note fields** were regenerated for the September baseline boundary or shifted
same-minute selected-event ordinals. The original 224,745-byte block is no longer a
prefix after chronological September insertion. `preservation_2025.json` records
old/new hashes, additions and the seven-field multiset containment check.

Ordinary rebuild still refuses missing/incomplete/corrupt/truncated evidence before
changing either output, including a previously retrieved zero-row listing. The
explicit one-time `--extend-window` path permits note changes only when the old row
matches the old-window reconstruction from the same raw evidence and all seven
non-note fields remain in the expanded export. Tests cover both successful
migration and refusal with missing evidence. The catalog-correction helper now
protects records by containment, not an obsolete byte-prefix check.

### Tracking coverage fixes the analysis blanks

Added **286 rows** to `analysis/config/history_coverage.csv`: one for each retrieved
momo/PChome series whose saved last point is after November 25. They cover
September 1-November 25 and cite the actual continuation timestamp. **No stopped
series receives coverage**: all 13 previously flagged cases and FOOD-006 momo are
excluded. Coverage never invents a change point or supplies a price before the
first source observation.

The validator checks coverage inventory, dates and continuation notes, and raw mode
cross-checks the status first/last timestamps against the source. The real-data R
smoke build produces **600 rows** with no error. Missing 2025 Nov 11 prices are now
**15** (reviewer's original count: 149); incomplete pre-sale histories are **22**
(original count: 151). Remaining blanks reflect source coverage, not absent
continuation declarations.

### Four exact histories recovered

After the user manually signed into ordinary Chrome and handled Chrome's console
warning, the approved same-origin history request ran **once per exact ID**. Request
starts were 5.921, 6.600 and 6.128 seconds apart; no retry, search sweep, proxy,
credential export or broad rerun was used. Each response is saved as gzip raw
evidence; the earlier UI search failures are archived.

| Listing | Exact history ID | HTTP | Raw points | Added change/baseline rows |
|---|---|---:|---:|---:|
| APPL-020 momo | `tw_pec_momoshop-13903670` | 200 | 76 | 15 |
| APPL-020 PChome | `tw_ec_pchome24h-DMBI4K-A900INYCB` | 200 | 30 | 14 |
| BEAU-020 PChome | `tw_ec_pchome24h-DDAB4W-A900HAV8C` | 200 | 50 | 19 |
| FOOD-002 PChome | `tw_ec_pchome24h-DBAY5B-A900J35DD` | 200 | 35 | 4 |

The **52 new rows** use the actual **2026-10-28 Taiwan collection date**. History ID,
shop, product ID, URL and TWD currency were checked before accepting evidence.
The problem was the UI search-discovery route, not unavailable exact histories.
Repeated equal observations were collapsed, explaining why raw point counts exceed
exported change counts. FOOD-002's title spans original/cream/cheese flavours; its
parent-ID rows explicitly flag that ambiguity rather than claiming a proven flavour.

## Retained flags and team disposition

These are retained source/catalog limitations, **not pending team decisions**:

- **3C-010 momo:** retain its six 2025 rows and SHORT/variant notes; no further work.
  Saved parent metadata lists blue and gray child IDs, while the selected gray UI
  has only 2026 points. Parent-versus-variant scope is a possible explanation, not
  a proven request-level cause; the data is not relabeled as verified gray history.
- **APPL-003 Coupang:** the saved listing is EH-NE57-P pink while the catalog says
  EH-NE57-A blue. Its original 30 October-window rows and warnings remain; no
  substitution or relabeling. Coupang is outside the analysis.
- **HOME-013 Coupang:** 750ml x1 remains unconfirmed; the saved selected link differs
  from the catalog SKU and a prior retailer detail check was denied. Keep the
  recorded zero-row reason; no more collection is requested for Coupang flags.
- All SHORT, MISMATCH and UNCERTAIN products stay. The nine title-variant listings
  named by the team are listed in README for later H1-H4 sensitivity checks.
- Stopped series stay unknown after their last observation; no coverage extension.

**34 distinct chart reviews** remain recorded: 25 exact matches, six catalog-option
corrections, one moving-window baseline qualification, one SSD discrepancy and one
unconfirmed Coupang option. The team accepted these as the approximately 10% check.
They describe the original October-November website review; September reconstruction
is not misrepresented as a new browser review. The old API repeat file remains
header-only. The original 116-history partial bundle covered Electronics (72) and
Appliances (44) only, with zero Beauty, Food or Home; current coverage spans all five.

## Verification and reproducibility

- **26 Node tests passed**, including the original destructive-rebuild regressions,
  new September baseline/migration guards and protected-record containment.
- **10 BigGo Python tests passed**, including clean-checkout CSV-only mode,
  explicit raw-mode failure without evidence and rejection of stopped-series coverage.
- **6 analysis Python tests and the complete R analysis regression suite passed.**
- CSV-only and independent raw-to-CSV validation pass for **3,908 rows / 334 histories**.
  Status and failure evidence account for all 335 targets; minimum logged gap 5.199s.
- Ordinary full-evidence rebuild leaves the current CSV byte-for-byte unchanged.
- Exact Section 11 schema/order, Taiwan time, collection dates, UTF-8, identifiers,
  chronology, integer prices, changes/reversals, baselines and warnings are checked.
- Saved evidence includes **120 UTC-millisecond API responses** and **214 visible
  Taiwan-minute tables**. Visible observations do not claim hidden milliseconds.
- No 2026 study dataset, products/catalog definitions or secrets were added.

Current CSV SHA-256: `8ee9dfd4a75baedd2d2c74762213457f225e0b819c7dbfb7d493946a633a4e9a` (1,029,090 bytes).
Raw evidence remains gitignored and is distributed separately. A fresh checkout
supports CSV-only validation; full reconstruction requires restoring `biggo/raw/2025/`.
The evidence bundle also includes the tracking-coverage file required by validation.
The current merged specification is unchanged by this PR; only BigGo deliverables
and the requested analysis coverage differ from main. PR #11 is never merged by
this task.
