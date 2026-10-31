# Latest analysis data

[Download the CSV](final_analysis.csv) or browse it directly on GitHub.

- **Analysis as of (Taiwan date): 2026-10-31**
- **Latest collected snapshot date: 2026-10-31**
- **Rows: 600** (one product x platform x year)

This is the latest cumulative analysis view. The automatic analysis workflow
replaces this same file after a real collection or an analysis-input update.
Only changed CSV/README contents are committed; skipped backup runs do not
publish data. Earlier versions remain available in Git history.

## Reading the table

- Filter `year = 2026` and use `latest_*` columns for current momo/PChome
  observations. `latest_fetch_status` identifies failures; missing current prices
  are not replaced with older successful prices.
- Filter `year = 2025` and use `listed_price`, `october_median` and
  `presale_change` for available BigGo historical measures.
- The unprefixed price/discount/gap columns describe the November 11 research
  event. The current-price preview is kept separate from those outcomes.
- `NA` means unavailable or not yet calculable, not zero. Consult
  `missing_reasons`, `analysis_status` and `ready_*` before analysing results.
- Discount rates are fractions: `0.20` means 20%; a gap of `0.10` means
  10 percentage points. Widen date columns if Excel shows `########`.

For definitions, assumptions and review requirements, see
[the analysis guide](../analysis/README.md). Individual platform CSVs, cumulative
snapshots, raw pages and build manifests remain in the GitHub Actions artifacts;
they are not copied into this directory. Existing unrelated data folders are
preserved. This CSV contains both current observations and provisional results;
its filename does not imply that all hypothesis tests are ready.
