# pba-project-the-janggals

Team **The Janggals**, ISS4066 Programming for Business Analytics, NTHU, Fall 2026.

## Topic

Are Double 11 discounts real? We track 150 products on momo and PChome (and Coupang through
BigGo history only) and compare each Nov 11 "discount" with the product's lowest price in the
previous 30 days (the EU benchmark), using BigGo price history for 2025 and 2026 plus our own
daily snapshots of each momo and PChome page's crossed-out "original price".

## Team

- Marvin Chandra
- Jordan Tjiang
- Alicia Joely
- Audrey Priscilla Wijaya
- Nicholas Albert Aklin

## Repo layout

Each task has its own folder.

| Folder | Owner | Output |
|---|---|---|
| [`products/`](products/) | Alicia, Audrey | `products/products.csv`, the 150 products we track |
| [`scrapers/momo/`](scrapers/momo/) | Jordan | Daily price snapshots from momo |
| [`scrapers/pchome/`](scrapers/pchome/) | Albert | Daily price snapshots from PChome |
| [`scrapers/coupang/`](scrapers/coupang/) | Marvin | Retired 2026-10-20 (Coupang uses BigGo history only) |
| [`biggo/`](biggo/) | Albert | `biggo/price_changes.csv`, BigGo price history for 2025 and 2026 |

The scrapers are built to [`scrapers/data-collection-spec.md`](scrapers/data-collection-spec.md).

## momo recorder

Run `Rscript scrapers/momo/scrape_momo.R` from the project root. The default input is
`products/products.csv`; a first positional argument selects a test table. See
[scrapers/momo/README.md](scrapers/momo/README.md) for setup, tests and verification evidence.

## Data

**Latest analysis table:** [`data/final_analysis.csv`](data/final_analysis.csv).
It updates automatically after analysis builds; [`data/README.md`](data/README.md)
shows its collection date and explains how to read it. Earlier versions are in
Git history, while individual scraper outputs and combined snapshots remain in
Actions artifacts.

The **combined snapshots** and **final analysis** Actions workflows automatically
build cumulative observations and the product-platform-year analysis table after
scraping. Historical production artifacts are backfilled, and missing evidence is
flagged rather than filled. Download `combined-snapshots` and `final-analysis` from
their respective Actions runs. See [`analysis/README.md`](analysis/README.md) for
schemas, calculation rules, review inputs and local rebuild commands.

Scraper output and raw pages stay out of git (`output/` and `raw/` folders are ignored). BigGo
history is collected from biggo.com.tw into `biggo/price_changes.csv`, which is tracked. Download
links will be added at Milestone 2.
