# data/

**Everything the analysis needs is in this folder.** Every other folder in the repo holds the
code and notes that produced these files, so you never have to look there to start working.

<!-- status:start -->
- `scrapes.csv`: **9,539 rows** from **33 scrape runs** (2 off-schedule), latest scheduled run **2026-11-13 15:07** (Taiwan time)
<!-- status:end -->

```
data/
  products.csv          the 150 products
  scrapes.csv           our momo + PChome scrapes, 2026      ─┐ analyse these
  biggo.csv             BigGo's daily price history, 2025    ─┘
  grids/                one wide price table per platform, for browsing in Excel
  source/               the untouched originals the files above are built from
```

| File | One row is | How it updates |
|---|---|---|
| [`products.csv`](products.csv) | a product we track (150) | Copy of `products/products.csv`, refreshed automatically |
| [`scrapes.csv`](scrapes.csv) | one listing (product on a platform) in one scrape run, Oct 19 to Nov 25, 2026 | Rebuilt after every scrape |
| [`biggo.csv`](biggo.csv) | one listing on one day, Sep 1 to Nov 25, **2025**, from BigGo | Rebuilt when the BigGo history changes |
| [`grids/momo_price_grid.csv`](grids/momo_price_grid.csv), [`grids/pchome_price_grid.csv`](grids/pchome_price_grid.csv) | a product; one column per date | Rebuilt after every scrape |
| [`source/snapshots.csv`](source/snapshots.csv) | every page our scrapers requested, failures included | After every scrape |
| [`source/biggo_price_changes.csv`](source/biggo_price_changes.csv) | one price change BigGo recorded | By the BigGo collection in [`biggo/`](../biggo/) |

All files are generated: don't edit them by hand. They join on `product_id`, plus `platform` where
they have it. Prices are whole NT$. `NA` means "not shown" or "unknown", never zero.

The files are designed to hold **facts, not analysis choices**. There is no 30-day benchmark or
discount percentage column: how to compute them is up to the analysis (recipes below).

## Loading the data

```r
library(readr)
products <- read_csv("data/products.csv")
scrapes  <- read_csv("data/scrapes.csv")
biggo    <- read_csv("data/biggo.csv")
```

Paths are from the repository root. From a `.qmd` in another folder, use `../data/scrapes.csv`.

- Base R works too: `read.csv("data/scrapes.csv", fileEncoding = "UTF-8")`.
- The files are UTF-8 **with a BOM**, so Excel shows the Chinese text when you double-click
  them. In Python, read them with `encoding="utf-8-sig"`, or the first column name gets a
  hidden character.
- Times are Taiwan time. readr labels `run_started_at` as UTC; the clock time is still Taiwan's.

## `scrapes.csv`: our own scrapes (2026)

Only pages that were read successfully, and only listings in the current product table. Failed
pages, and the first run's listings that later left the table, stay in `source/snapshots.csv`.

| Column | Content |
|---|---|
| `date` | Taiwan date of the scheduled run (see `slot`) |
| `slot` | The scheduled run this belongs to: `15:07`, or `18:07` / `23:07` on Nov 10 to 12. `off-schedule` for runs that started more than an hour after any slot |
| `run_started_at` | When the run actually started, Taiwan time |
| `platform` | `momo` or `pchome` |
| `product_id` | Joins to `products.csv` |
| `brand`, `model`, `category` | Copied from `products.csv`, so everyday work needs no join |
| `sale_price` | The headline price, before any conditional reduction |
| `original_price` | The crossed-out 原價 / 市價. `NA` if the page showed none |
| `extra_price` | The lowest further price shown with a condition (member, time-limited, card). `NA` if none |
| `extra_price_label` | The label next to `extra_price`, in Chinese |
| `lowest_shown_price` | The lower of `sale_price` and `extra_price`. **Compare this one with BigGo** |
| `single_item_price` | PChome only: `sale_price` with an "any one item" 折 offer applied, rounded down. `NA` if there's no such offer |
| `price_note` | Why a price is derived or may be incomplete (see below). `NA` if nothing to note |
| `promo_tag` | Sale or campaign labels as shown; several are joined with ` \| ` |
| `coupon_note` | Coupon or card wording |

One price per listing per day: `filter(scrapes, slot == "15:07")`. A row is identified by
`run_started_at` + `platform` + `product_id`; for scheduled runs `date` + `slot` is enough too.

Things to know:

- **Runs and slots.** Scrapes run daily at 15:07, plus 18:07 and 23:07 on Nov 10 to 12. The
  first two runs (Oct 19 and 20) started hours late and count as their day's 15:07. A run that
  started more than an hour after its slot saw different prices, so it is `off-schedule` under
  its own start date: the Oct 21 01:26 test run, and the Nov 12 06:13 run that replaced the
  missed Nov 11 23:07 run (it saw post-Double-11 prices, so it is not labelled Nov 11).
- **`original_price` differs by platform.** On momo it's the 市售價, and in our data it never
  changes for a listing. On PChome it's any struck-through price, which can equal `sale_price`.
- **`extra_price` isn't comparable across platforms.** momo shows its 限時折後價 as a price.
  PChome often writes a discount as a 折 condition instead, which the scraper can't always link
  to a price. `single_item_price` recovers it when any single item qualifies
  (`任選1件享95折`, `滿1件享9折`): `sale_price` × rate, rounded down, which matched BigGo in 5 of 5
  checks. Basket offers such as `滿$2000折$150` are not item prices and are left alone.
- **`price_note`** says either which 折 rate `single_item_price` used, or, for PChome rows where
  the crossed-out price equals `sale_price` and no other price was found, that a discount may be
  missing. Check those against BigGo once the 2026 history is in.
- **Dropped scraper columns** are still in `source/snapshots.csv`. They are: `shown_discount_pct`
  (always empty: neither site shows "% off" badges), `seller_type`, `in_stock` and `source`
  (the same on every successful row), `fetch_status` and `http_status`, `scraped_at`,
  `platform_item_id` and `run_id`.

## `biggo.csv`: BigGo's price history (2025)

| Column | Content |
|---|---|
| `date` | The day, 2025-09-01 to 2025-11-25 |
| `platform` | `momo` or `pchome` |
| `product_id`, `brand`, `model`, `category` | As in `scrapes.csv` |
| `price` | The price in effect at **15:07 Taiwan time** that day, the same time our scrapers run |
| `price_set_at` | When BigGo recorded that price (the change it came from), Taiwan time |

How it is built (full rules at the top of [`build_biggo_daily.R`](../biggo/scripts/build_biggo_daily.R)):

- BigGo records a price only when it changes. Each day takes the last change at or before 15:07.
- **A missing day means we can't vouch for the price**, not that the product was absent: the
  listing's BigGo history had not started yet, or BigGo stopped recording it.
- **BigGo's `price` is the lowest price on the page**, so compare it with `lowest_shown_price`,
  never with `sale_price`. On Oct 22, 45 of the 46 momo listings that showed an `extra_price`
  matched BigGo on it.
- Coupang is excluded (team decision, Oct 27). Its history is still in `source/biggo_price_changes.csv`.
- 2026 BigGo history is due Nov 29 and will be added in the same shape.

## `grids/`: for browsing only

One row per product sold on the platform, one column per date, and the 15:07 `sale_price` in each
cell. Read across a row for one product's history, or down a column for one day. A grid holds one
price per cell, with no crossed-out price and no BigGo, so do the analysis from `scrapes.csv`.

## `source/`: the originals

- `snapshots.csv`: every scrape exactly as the scrapers wrote it (the 17 columns of
  [spec section 7.1](../scrapers/data-collection-spec.md#71-columns-exact-names-this-order) plus
  `run_id`), failed pages included.
- `biggo_price_changes.csv`: one row per BigGo price change, in the format of
  [spec section 11](../scrapers/data-collection-spec.md#11-biggo-price-history-format-datasourcebiggo_price_changescsv).
  Use it when once a day is not enough, for example to find a flash sale that started after
  15:07 and ended before 15:07 the next day. Its `note` column flags listings whose BigGo title
  doesn't exactly match our product (see "Team decisions" in [`biggo/README.md`](../biggo/README.md)).

## Recipes

The lowest price in the 30 days before a date, per listing (a rolling version of the EU benchmark;
the EU rule counts back from the day the reduction *started*, so choose the window that fits your question):

```r
library(dplyr)
daily <- scrapes |> filter(slot == "15:07")
day   <- as.Date("2026-11-11")
benchmark <- daily |>
  filter(date >= day - 30, date < day) |>
  group_by(platform, product_id) |>
  summarise(min_30d = min(lowest_shown_price), days_seen = n(), .groups = "drop")
nov11 <- daily |> filter(date == day) |> inner_join(benchmark, by = c("platform", "product_id"))
```

Our 2026 scrapes start Oct 19, so a 30-day window before Nov 11 has at most 23 days; keep
`days_seen` in view. 2025 works the same way on `biggo.csv` with `price`.

## What used to be here

- `snapshots.csv` and `biggo_price_changes.csv` moved to `source/` on 2026-11-12, and
  `biggo_daily.csv` became `biggo.csv` (same prices, plus `brand`, `model`, `category`).
- `final_analysis.csv` was removed on 2026-11-02: it mixed a live price preview with unfinished
  Nov 11 calculations. Its last version, and the R code that built it, are in git history at
  commit `4b97f51`. The raw scraper CSVs and saved HTML pages of each run stay in that run's
  GitHub Actions artifacts.
