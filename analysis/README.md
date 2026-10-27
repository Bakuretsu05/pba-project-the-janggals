# Automated analysis datasets

The scraping jobs and their original momo/PChome artifacts are unchanged.
Two downstream workflows build the research datasets without sending any new
requests to shopping sites:

1. **combined snapshots** (`combined-snapshots.yml`) runs when `scrape` finishes on
   `main`. It skips scheduled backups that produced no scraper artifacts. It also
   supports **Run workflow** for an initial historical backfill. A push changing
   its collector, product metadata or workflow rebuilds the combined dataset.
2. **final analysis** (`final-analysis.yml`) runs after the combined dataset is
   published. Updating BigGo history, analysis decisions or the R builder also
   rebuilds the analysis; **Run workflow** is available for manual refreshes.

Open the corresponding Actions run and download its artifact:

| Artifact | File | Observation |
|---|---|---|
| `combined-snapshots` | `combined_snapshots.csv` | product x platform x scraping run, cumulative |
| `combined-snapshots` | `runs/combined_<run_id>.csv` | both platforms for a single scraping run |
| `combined-snapshots` | `snapshot_runs.csv` | row counts, successful rows and platform-pair coverage per run |
| `combined-snapshots` | `snapshot_manifest.json` | source artifact IDs, unavailable/excluded inputs and build time |
| `final-analysis` | `final_analysis.csv` | product x platform x year (2025 and 2026) |

With the current product table, a complete collection has 300 rows and the analysis
table has 600. Early production runs used smaller tables: keep their actual rows;
do not invent missing observations. A missing platform is marked in
`snapshot_runs.csv`; collection failures remain rows with their original status.
Non-main runs and pre-collection smoke tests are excluded. Production artifacts
whose product IDs differ from their own commit's full product table are recorded
as `product_set_mismatch` in the manifest rather than treated as full collections.

## History and provenance

Each build seeds itself from the latest successful **non-empty** combined artifact,
then imports any unseen production scrape artifacts. Previously recovered rows
therefore survive expiry of their original raw-page artifacts. Expired artifacts
that were never recovered cannot be restored; their IDs are recorded in the
manifest. Combined and analysis artifacts are retained for 90 days: download and
archive the final cumulative outputs before those artifacts expire after the
project stops running. Rerunning a scraper replaces that run's older platform
artifact with the newest artifact, without duplicating observations.

The combined data keeps all 17 scraper columns and adds `snapshot_id`, source
run/artifact IDs, source commit, run time, conclusion, and product brand/model/category.
`source_run_attempt` is the attempt reported by GitHub when the artifact was first
imported. Actual per-product timestamps stay in `scraped_at`, in Taiwan time.
`run_started_at` is the platform's timestamp encoded in its artifact name, not the
intended timer slot. Neither date alone nor a rounded collection slot is a unique
key; use `(source_run_id, platform, product_id)`.

## Analysis rules and outstanding evidence

### Current-price preview

`final_analysis.csv` also contains the observations already collected, before
the Nov 11 event is available. The preview columns appear immediately after
`analysis_as_of`:

- `latest_snapshot_date`, `latest_scraped_at`, `latest_run_id`, and
  `latest_fetch_status` identify the latest actual observation for that listing-year.
- `latest_original_price`, `latest_sale_price`, `latest_extra_price`, and
  `latest_extra_price_label` copy its observed prices and offer label.
- `latest_listed_price` applies the unconditional-price rule below;
  `latest_advertised_discount` compares it with that observation's reference price.
- `observed_snapshot_count`, `observed_ok_count`, `observed_days`, and
  `first_observed_date` describe collection coverage so far.
- `observed_min_listed_price` and `observed_max_listed_price` summarize valid prices
  in the collected snapshots. They are not complete 30-day BigGo benchmarks.

Only observations in the row's year, up to the build's as-of date, are included.
A failed latest scrape keeps its failure status and missing prices; older prices
are not presented as current. The observed minimum/maximum may still summarize
earlier successful collections, with counts showing the available coverage.
2025 rows have no snapshot preview unless actual 2025 snapshots are supplied.

The existing unprefixed `original_price`, `listed_price`, discounts, gaps, and
readiness flags continue to describe the Nov 11 research event. They do not
borrow the preview prices. On an ongoing project, preview values can therefore
be populated while the event outcomes correctly remain pending.

The calculations live in base R, following the Milestone 2 proposal. Rates are
fractions: `0.20` means 20%; a gap of `0.10` means 10 percentage points. No missing
reference price is filled from another day, another platform or BigGo. Advertised
discounts are unavailable in 2025, which has no live reference-price observations.

- **2026 event observation:** select the earliest actual Nov 11 production run for
  each platform. Preserve failures in that run instead of choosing a later successful
  or cheaper row. Override the run per listing with `event_decisions.csv` if the
  team decides to use another of the three planned slots. There is no universally
  correct choice of slot; this explicit default is reproducible.
- **Listed price:** ordinary `sale_price`, or the lower time-limited `extra_price`.
  Member, coupon, card, points, spend-threshold and unknown conditional prices are
  not substituted. The extra price must have a time-limited label with none of
  those other conditions. Failed observations have no listed price.
- **2025 price and BigGo daily benchmarks:** last known change at or before 15:07
  Taiwan time each day. This is a fixed-time daily convention, not an intraday
  minimum. Retain the original change points for sensitivity analyses of flash
  sales; the proposal does not specify a unique intraday aggregation rule.
- **Coverage:** by default carry prices only between observed BigGo timestamps.
  A reviewer can extend this to a verified tracking interval in
  `history_coverage.csv`. A last price point alone never proves that tracking
  continued. The latest price before the interval is still required.
- **Event start:** `price_start_date_candidate` shows the start of the final
  matching BigGo price stretch before Nov 11. It is a suggestion, not proof of
  campaign onset. A reviewed `price_start_date` in `event_decisions.csv` is required
  before publishing the 30-day or regular-price benchmark.
- **30-day low:** all 30 daily prices immediately before the reviewed start date
  must be known. An early start may require September data. Do not shorten the
  window or substitute a partial minimum.
- **Regular price:** median of known daily prices from Oct 1 through the day before
  event onset, excluding days more than 5% below the complete October median and
  all reviewed platform campaign dates. Requires a complete baseline and
  `campaigns_reviewed=TRUE` for that product/platform/year. Without calendar review
  the regular benchmark remains missing.
- **Pre-sale change:** median Nov 1-10 versus the complete October median. Both
  periods must be fully covered. It is computed independently of original prices.

The remaining measures follow the proposal's formulas:
`advertised_discount`, `real_discount`, `regular_discount`, `gap`, `gap_regular`.
Negative discounts are kept, not truncated. `ready_h1_h3`, `ready_h2_h4`,
`analysis_status`, and `missing_reasons` distinguish a usable result from a pending
event, missing history or an unreviewed decision. The `ready_h2_h4` flag means the
listing-year's inputs are available; a year-to-year comparison still needs its
matching product/platform in the other year.

The BigGo input currently contains its header only. The automatic build still
publishes all 600 rows with truthful missing values and flags; the workflow does
not collect BigGo history or claim that today's incomplete table is final evidence.
Retired Coupang listings remain outside this two-platform table.

### Review inputs

These tracked CSVs start with headers only; add evidence rather than guessed values:

- `config/event_decisions.csv`: one row per product/platform/year. Set a reviewed
  event start, optional `snapshot_run_id`, and `campaigns_reviewed` (`TRUE`/`FALSE`).
  Explain the evidence in `note`. Review the observed Nov 11 price before confirming
  the start of its particular price spell.
- `config/history_coverage.csv`: one row per verified tracking interval, dates
  inclusive, with the supporting evidence in `note`.
- `config/campaign_periods.csv`: one row per inclusive campaign date range.
  `platform` is `momo`, `pchome` or `all`; enter both years where applicable.

## Local rebuild and tests

From the repository root, with GitHub CLI authenticated:

```powershell
python analysis/collect_snapshots.py --repo Bakuretsu05/pba-project-the-janggals
Rscript analysis/build_analysis.R
```

For the first local backfill before the workflow exists, add `--no-seed` to the
collector. To reuse a local cumulative dataset, pass `--seed-dir output/combined`.
Outputs go to ignored `output/combined` and `output/analysis`. The R script takes
optional positional arguments: snapshot CSV, output directory, as-of Taiwan date.

```powershell
python -m unittest discover -s analysis/tests -p 'test_*.py' -v
Rscript analysis/tests/test_analysis.R
```

CI runs these tests on pipeline changes. The R tests cover benchmark math,
time-limited versus member prices, missing references, failed first observations,
future events, unreviewed starts and incomplete coverage.
