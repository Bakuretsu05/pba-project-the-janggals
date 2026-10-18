# momo scraper

Owner: **Jordan**. Contract: [../data-collection-spec.md](../data-collection-spec.md).

## Run from the project root

```powershell
Rscript scrapers/momo/install_dependencies.R
Rscript scrapers/momo/scrape_momo.R
```

Set SCRAPER_CONTACT in a root .Renviron file locally, or in the existing GitHub repository
secret for Actions. The local contact has been migrated from the earlier PBA_CONTACT_EMAIL
setting. The secret must be supplied by the repository owner; it is never committed.

The default input is the team's products/products.csv. A first positional argument selects
a different table, exactly as the workflow expects:

```powershell
Rscript scrapers/momo/scrape_momo.R scrapers/momo/tests/products_test.csv
Rscript scrapers/momo/scrape_momo.R scrapers/momo/tests/products_errors.csv
Rscript scrapers/momo/tests/test_momo.R
```

On Jordan's Windows machine Rscript is not on PATH; use
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' followed by the same script and arguments.

## Input and output

The input uses the ten shared columns in spec §6.1. No extra item-code, title or variant
columns are required. The scraper derives the item ID from momo_url, accepting both
GoodsDetail.jsp?i_code=... and /product/ID links with tracking parameters. It requests
a rebuilt canonical https://www.momoshop.com.tw/product/ID URL, without tracking.
Search links or other hosts are bad_input rows. Empty momo links are skipped; duplicate
product IDs produce bad_input rows without preventing other products from running.

Each run creates:

- output/momo_YYYY-MM-DD_HHMM.csv: the shared **17 columns**, ending in fetch_status.
- raw/YYYY-MM-DD_HHMM/ITEM.html.gz: the response used for the row.
- raw/YYYY-MM-DD_HHMM/ITEM__attemptN.html.gz: earlier received responses, if any.
- raw/YYYY-MM-DD_HHMM/verification.json: request counts, parse errors and coverage notes.

Run date/time are fixed at startup in Asia/Taipei. scraped_at is the actual first request
timestamp, or NA for an unrequested row. An existing same-minute output is never overwritten
or appended to; the run stops before any request. Output/raw are git-ignored and the team's
existing Actions workflow uploads them as artifacts.

The summary and exit code match the shared workflow: zero if at least one row is ok, one if
none is ok or startup fails. Every included product gets a row. Requests have a 30-second
timeout and at least five seconds between starts. Timeouts, connection errors, 429 and 5xx get
one retry after 60 seconds. Blocks get one bounded alternate study-identified user agent;
remaining blocks are recorded and later products still run. Browser/proxy fallbacks are
**not implemented**: this is incomplete coverage of spec §8.2, not a claim to defeat every block.
No authentication or credentials are used to fetch products.

## Price mapping and limits

The parser checks visible 品號 and JSON-LD source ID, TWD currency and the headline/schema
amount. It supports the verified modern data-testid price layout with one hasVariant entry.
Multi-option or unrecognized layouts give parse_failure; no arbitrary option is selected.

- 市售價 / 市價 / 原價 → original_price.
- 促銷價 / 售價 → sale_price, even when crossed out beside a further offer.
- Explicit conditional amount such as 限時折後價 → extra_price and its exact label.
- JSON-LD may contain the conditional amount; it is never blindly used as sale_price.
- Promo/coupon/card text is copied from the purchase area, with shared whitespace rules.
  折 stays text; no discount, per-unit price or cashback amount is calculated.
- seller_type follows the provisional regular-catalogue rule, with visible third-party
  markers reported as marketplace. This is not a legal seller audit.
- Explicit sold-out/removed notices produce ok with in_stock FALSE. A generic missing page
  without a selling price or removed notice is parse_failure. Other failed rows have NA stock.

Interactive offers, hidden coupon prices, image-only labels and all marketplace/sold-out
layout variants have not been exhaustively verified. The momo “check” cells that are still
unresolved remain open in the shared spec. ok certifies the supported price/sold-out criterion,
not full promotion coverage or cross-platform sample eligibility.

robots.txt was checked 2026-10-18 for the public /product/ and GoodsDetail.jsp paths.
No /api/ or /ajax/ price endpoint is requested; robots is checked by the builder rather than
parsed at runtime, following the latest spec. The product-selection team owns matching the
exact physical product across platforms; links can be completed independently of this code.

## Evidence and tests

The seven real links are in tests/products_test.csv. The integrated recorder was rerun
successfully on all seven using the shared URL-only input and 17-column output. See
[VERIFICATION.md](VERIFICATION.md). Live generated files stay in ignored output/ and raw/.

tests/evidence/ retains the earlier 16-column prototype observations and their dated
verification report. They are historical test evidence, not current production snapshots.
The earlier 93-product review queue is also retained there for reference; it does not control
the team's shared product table or block the new URL-only reader.
