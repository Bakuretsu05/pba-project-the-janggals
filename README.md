# pba-project-the-janggals

Team **The Janggals**, ISS4066 Programming for Business Analytics, NTHU, Fall 2026.

## Topic

Are Double 11 discounts real? We track about 100 products on momo, PChome and Coupang and
compare each Nov 11 "discount" with the product's lowest price in the previous 30 days (the
EU benchmark), using BigGo price history for 2025 and 2026 plus our own daily snapshots of
each page's crossed-out "original price".

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
| [`products/`](products/) | Alicia, Audrey | `products/products.csv`, the ~100 products we track |
| [`scrapers/momo/`](scrapers/momo/) | Jordan | Daily price snapshots from momo |
| [`scrapers/pchome/`](scrapers/pchome/) | Albert | Daily price snapshots from PChome |
| [`scrapers/coupang/`](scrapers/coupang/) | Marvin | Daily price snapshots from Coupang |

The scrapers are built to [`scrapers/data-collection-spec.md`](scrapers/data-collection-spec.md).

## momo recorder

Run `Rscript scrapers/momo/scrape_momo.R` from the project root. The default input is
`products/products.csv`; a first positional argument selects a test table. See
[scrapers/momo/README.md](scrapers/momo/README.md) for setup, tests and verification evidence.

## Data

Scraper output and raw pages stay out of git (`output/` and `raw/` folders are ignored). BigGo
history is copied by hand from biggo.com.tw. Download links will be added at Milestone 2.
