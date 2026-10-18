# pba-project-the-janggals

## momo recorder

The initial momo-only recorder is implemented for seven confirmed single-option products.
See [run instructions](scraper/README.md), [active input](data/products.csv),
[remaining 93-product review queue](data/momo-review-queue.json), and
[verification results](momo-verification.md). The original `Productss.csv` is unchanged.

Run from the repo root: `Rscript scraper/scrape_momo.R`.

Team **The Janggals**, ISS4066 Programming for Business Analytics, NTHU, Fall 2026.

## Topic

Are Double 11 discounts real? We track about 100 products on momo, PChome and Coupang and
compare each Nov 11 "discount" with the product's lowest price in the previous 30 days (the
EU benchmark), using BigGo price history for 2025 and 2026 plus our own daily snapshots of
each page's crossed-out "original price".

## Team

- Marvin Chandra
- Jordan Tjiang

## Data

Daily momo records live in `data/snapshots/`. Raw momo pages live in `raw/momo/`, which git
ignores; `data/raw/` remains ignored as well. The team must back up raw captures to its shared
Google Drive; the recorder does not upload them. BigGo history is copied by hand from
biggo.com.tw. Download links will be added at Milestone 2.
