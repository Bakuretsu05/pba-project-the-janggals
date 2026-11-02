# data/

**Everything the analysis needs is in this folder.** Every other folder in the repo holds the
code and notes that produced these files, so you never have to look there to start working.

<!-- status:start -->
- `snapshots.csv`: **4,690 rows** from **16 scrape runs**, latest collection **2026-11-02** (Taiwan date)
<!-- status:end -->

| File | One row is | Rows | How it updates |
|---|---|---|---|
| [`products.csv`](products.csv) | a product we track | 150 | Copy of `products/products.csv`, refreshed automatically. Don't edit this copy |
| [`snapshots.csv`](snapshots.csv) | one product on one platform (momo or PChome) in one run of our scrapers, Oct 19 to Nov 25, 2026 | grows by ~300 per run | Automatically after every scrape. Don't edit |
| [`biggo_daily.csv`](biggo_daily.csv) | one product on one platform on one day, Sep 1 to Nov 25, **2025**, from BigGo | 24,246 | Automatically rebuilt from `biggo_price_changes.csv`. Don't edit |
| [`biggo_price_changes.csv`](biggo_price_changes.csv) | one price change BigGo recorded | 3,908 | By the BigGo collection in [`biggo/`](../biggo/) |

All files join on `product_id`, and on `platform` too where they have it. Prices are whole NT$.
`NA` means "not shown" or "unknown", never zero.

## Loading the data in R

The paths below are from the repository root. From a `.qmd` in another folder, adjust them
(for example `../data/snapshots.csv`).

```r
products  <- read.csv("data/products.csv", fileEncoding = "UTF-8")
snapshots <- read.csv("data/snapshots.csv", fileEncoding = "UTF-8")
biggo     <- read.csv("data/biggo_daily.csv")
```

`fileEncoding = "UTF-8"` keeps product names and promotion labels readable on Windows.

## `snapshots.csv`: our own scrapes (2026)

The columns are the 17 the scrapers write ([spec section 7.1](../scrapers/data-collection-spec.md#71-columns-exact-names-this-order)),
plus `run_id`.

| Column | Content |
|---|---|
| `date` | Run date, Taiwan time |
| `scraped_at` | When this product's page was requested, Taiwan time. `NA` if no request was sent |
| `platform` | `momo` or `pchome` |
| `product_id` | Joins to `products.csv` |
| `platform_item_id` | The platform's own ID for the listing |
| `original_price` | The crossed-out 原價 / 市價. `NA` if the page showed none |
| `sale_price` | The headline price, before any conditional reduction |
| `extra_price` | The lowest further price shown with a condition (member, coupon, time-limited, card). `NA` if none |
| `extra_price_label` | The label next to `extra_price`, in Chinese |
| `shown_discount_pct` | A "% off" badge as displayed: `-23%` gives `23`. 折 badges stay in `promo_tag` |
| `promo_tag` | Sale or campaign labels; several are joined with ` \| ` |
| `coupon_note` | Coupon or card wording |
| `seller_type` | `platform` (sold by momo/PChome itself) or `marketplace` (third-party seller) |
| `in_stock` | `TRUE` / `FALSE`. `NA` unless `fetch_status` is `ok` |
| `http_status` | The page's HTTP status: `200`, `403`, `404`... |
| `source` | Always `scraper` |
| `fetch_status` | `ok`, or why the page could not be read: `parse_failure`, `http_error`, `timeout`, `blocked`, `bad_input` |
| `run_id` | The GitHub Actions run that collected the row |

Things to know:

- **A row is identified by `run_id` + `platform` + `product_id`.** `date` alone is not enough:
  on Nov 10, 11 and 12 the scrapers run three times a day (15:07, 18:07 and 23:07); on the
  other days, once at 15:07.
- **Failed pages are kept as rows**, with their `fetch_status` and `NA` prices. Filter
  `fetch_status == "ok"` before using prices.
- A product not sold on a platform has no rows for that platform.

## `biggo_daily.csv`: BigGo's price history (2025)

| Column | Content |
|---|---|
| `date` | The day, 2025-09-01 to 2025-11-25 |
| `platform` | `momo` or `pchome` |
| `product_id` | Joins to `products.csv` |
| `price` | The price in effect at **15:07 Taiwan time** that day, the same time our scrapers run |
| `price_set_at` | When BigGo recorded that price (the change it came from), Taiwan time |

How it is built (full rules at the top of [`build_biggo_daily.R`](../biggo/scripts/build_biggo_daily.R)):

- BigGo records a price only when it changes. Each day takes the last change at or before 15:07.
- **A missing day means we can't vouch for the price**, not that the product was absent: the
  listing's BigGo history had not started yet, or BigGo stopped recording it. Prices are carried
  forward only while BigGo was still tracking the listing.
- Coupang is excluded (team decision, Oct 27). Its history is still in `biggo_price_changes.csv`.
- BigGo shows one price per point. It is named `price`, not `sale_price`, because we can't
  prove it is the same figure our scrapers call `sale_price`.
- 2026 BigGo history is due Nov 29 and will be added in the same shape.

## `biggo_price_changes.csv`: the raw BigGo change points

One row per price change, in the format of
[spec section 11](../scrapers/data-collection-spec.md#11-biggo-price-history-format-databiggo_price_changescsv):
`product_id`, `platform` (`momo`, `pchome` or `coupang`), `biggo_url`, `changed_at` (Taiwan time),
`price`, `entered_by`, `entered_on`, `note`. The window is Sep 1 to Nov 25, 2025, plus the last
change before Sep 1.

Use it when a once-a-day price is not enough, for example to find a flash sale that started after
15:07 and ended before 15:07 the next day. The `note` column carries warnings about listings
whose BigGo title does not exactly match our product (SHORT / MISMATCH / UNCERTAIN). What those
mean, and which listings the team agreed to test with and without, is under "Team decisions" in
[`biggo/README.md`](../biggo/README.md#team-decisions-now-recorded-in-the-specification).

## `products.csv`: the 150 products

`product_id`, `brand`, `model`, `category` (`3C`, `APPL` small appliances, `BEAU`, `FOOD`, `HOME`),
the momo / PChome / Coupang links, and the BigGo search links. How they were chosen:
[`products/SELECTION_NOTES.md`](../products/SELECTION_NOTES.md).

## What used to be here

`final_analysis.csv` was removed on 2026-11-02: it mixed a live price preview with unfinished
Nov 11 calculations. Its last version, and the R code that built it, are in git history at
commit `4b97f51`. The raw scraper CSVs and saved HTML pages of each run stay in that run's
GitHub Actions artifacts.
