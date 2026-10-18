# momo integration verification

Checked 2026-10-18 against the latest shared scrapers/data-collection-spec.md and the
GitHub Actions command. This report concerns the integrated URL-only recorder, not the
earlier prototype.

## Results

- **38 offline checks passed** with Rscript scrapers/momo/tests/test_momo.R.
- **Seven real products returned ok** in the run started at 23:54 Taiwan time:
  output/momo_2026-10-18_2354.csv, with the shared 17-column header.
- The live error run at 23:58 used a bad URL, a nonexistent item and a valid SanDisk item,
  in that order. Results were bad_input, parse_failure (HTTP 200), and ok (669).
  Output: output/momo_2026-10-18_2358.csv. The command exited zero because one row was ok.
- Every received response was gzipped under the matching raw/YYYY-MM-DD_HHMM/ directory.
  No request or raw response file was created for the bad URL.
- The existing same-minute-file refusal, fixed run date across midnight, actual request
  timestamps, per-row duplicate handling, text encoding and exact response preservation
  are covered offline without touching the live output folders.

| Product | Original | Ordinary sale | Conditional |
|---|---:|---:|---:|
| SanDisk Ultra Flair 128GB | 899 | 669 | NA |
| Pocari original 580ml ×24 | 696 | 509 | NA |
| 3M pot/stove scourers, four pieces | 162 | 100 | NA |
| Original Coke 330ml ×24 | 600 | 340 | NA |
| Coke Zero 330ml ×24 | 600 | 340 | NA |
| Ferrero T16 / 200g | 299 | 275 | 233 |
| Evian 500ml ×24 | 1320 | 1200 | 1100 |

These are observed NT$ prices from the seven-product run, not calculated discounts.
The two conditional offers had the displayed label 限時折後價. SanDisk, Pocari and Ferrero
had also been compared with the live browser display during the original verification.
Price-role parsing is unchanged: the 233/1100 schema headline is not substituted for the
275/1200 ordinary selling price.

The missing-item test exposed momo's generic error page: it lists both 商品目前無展售 and
網頁不存在 as possible reasons. That message is not proof of a real removed product.
The parser was corrected to classify it as parse_failure; a specific confirmed removed or
sold-out notice still yields ok with in_stock FALSE. A regression check covers this distinction.
The earlier 23:57 diagnostic output predates that classification fix and is not the accepted
error-test result; it remains local in the ignored output folder.

## Integration

The entry point is scrapers/momo/scrape_momo.R. It reads products/products.csv by default,
or the first positional test-table argument, and uses SCRAPER_CONTACT. Both legacy i_code
links and modern /product/ID links work with tracking parameters; no extra metadata columns
are required. Unsupported multi-option/price layouts remain explicit parse_failure rows.

The teammate-owned products/products.csv was preserved as received from main. At integration
it contains a header only. Fill it with validated links before expecting the default workflow
to collect products; use tests/products_test.csv for a manual verification meanwhile.
No GitHub workflow run was triggered as part of this local integration.

The latest shared workflow, PChome scraper and Coupang code were preserved. Local settings,
installed R packages, live output and raw pages stay ignored. Historical prototype observations
are retained under tests/evidence/, explicitly labeled legacy; the old 16-column/appending
entry points and duplicate product table were removed.

## Limits

This verifies the input/output workflow and supported momo pages, not full sample eligibility,
all promotion widgets or every block workaround. One timeout/429/5xx retry after 60 seconds
and a bounded alternate study-identified user agent are implemented. Exhausted failures do
not stop later products. Browser/proxy fallbacks from spec §8.2 are not implemented, and
unverified seller/layout checks remain documented in README.md. The shared GitHub secret
and a populated product table are operational prerequisites owned by the team.
