# Data Collection Specification: Double 11 Price Study

This document is the single reference for every scraper and every hand-entered dataset in the
project. If your code and this document disagree, the document wins.

---

## 1. Background

Our final project asks: **when Taiwanese shopping platforms advertise Double 11 (Nov 11)
discounts, how much of the discount is real?** We compare each advertised discount with the
product's actual lowest price over the previous 30 days, the rule the EU uses for price
reductions.

The data comes from two sources:

- **Daily page snapshots (2026):** what each product page shows each day, including the
  crossed-out "original price". This can only be captured live; once a day has passed, that
  day's page is gone. **This is what the scrapers are for.**
- **BigGo price history (2025 and 2026):** every past price change for the same products. This
  can be read at any time and gives us the actual price series for both years.

## 2. What is needed

1. **Scrapers for momo, PChome and Coupang** that save one row per product per day in the
   format in section 6.
2. The scrapers **running every day** from Oct 19 to Nov 25, with extra runs around 11.11.
3. **BigGo price history transcribed** into the format in section 9.

Who builds what is not decided yet; owners go in the owner column in section 10.

## 3. Scope

**In scope**

- momo, PChome and Coupang product pages, for the products in the product table (section 5).
- BigGo price history for the same products.

**Out of scope**

- Shopee (excluded by design: marketplace structure and anti-bot protection).
- Any calculation: real discount, 30-day low, percentages. The analysis does this later in R.
- Anything behind a login, and any personal data.

---

## 4. Functional requirements

| ID | Requirement |
|---|---|
| **FR-1** | The scraper reads its product list from `data/products.csv` (section 5). No product IDs or URLs are hard-coded. |
| **FR-2** | For every product with an ID on that platform, it writes exactly one row per run, with the columns in section 6, in that order. |
| **FR-3** | A product that fails (error, 403, 404, timeout, parse failure) **still gets a row**: prices `NA`, the HTTP status in `http_status`. A failed row and a missing row must look different. |
| **FR-4** | Output goes to `data/snapshots/<platform>_<YYYY-MM-DD>.csv`. A second run on the same day appends rows, writing the header only once. |
| **FR-5** | The raw response for each product is saved gzip-compressed to `raw/<platform>/<YYYY-MM-DD>/<platform_item_id>.html.gz` (or `.json.gz`), so a parsing bug can be fixed later by re-parsing old pages. `raw/` is listed in `.gitignore` and backed up to the team's shared Drive. |
| **FR-6** | The scraper copies what the page shows. It never computes discounts, never fills a missing value from another day, and never translates or tidies labels. |
| **FR-7** | One command runs the whole thing: `Rscript scraper/scrape_<platform>.R` from the repo root. |
| **FR-8** | At the end of a run it prints a one-line summary: products attempted, products with a price, output file. |

## 5. Input: the product table `data/products.csv`

One row per product. The same physical product on several platforms is **one row** with several
platform IDs; that is how platforms get matched.

| Column | Example | Notes |
|---|---|---|
| `product_id` | `3C-001` | Category code + 3 digits. Never reused or renumbered |
| `brand` | `Apple` | |
| `model` | `AirPods 4 (ANC)` | Exact variant: size, colour, pack count |
| `category` | `3C` | `3C` electronics · `APPL` small appliances · `BEAU` beauty · `FOOD` snacks and drinks · `HOME` home and daily goods |
| `momo_i_code` | | From `GoodsDetail.jsp?i_code=...`. Empty if not sold on momo |
| `pchome_id` | | PChome product ID. Empty if not sold on PChome |
| `coupang_item_id` | | Number in the Coupang product URL |
| `coupang_url` | | Full Coupang product URL |
| `biggo_url_momo`, `biggo_url_pchome`, `biggo_url_coupang` | | BigGo listing to transcribe |
| `added_on` | `2026-10-11` | Date the product joined the list |

Target: about 100 products, about 20 per category, on as many platforms as possible.

Each product must:
- be sold on at least 2 of momo, PChome and Coupang, as the same variant (size, colour, pack count);
- be sold by the platform itself, not a third-party shop;
- have BigGo price history back to at least October 2025;
- be something students commonly buy.

## 6. Output: daily snapshot format

### 6.1 Columns (exact names, this order)

| # | Column | Type | Content |
|---|---|---|---|
| 1 | `date` | `YYYY-MM-DD` | Day of the run, Taiwan time |
| 2 | `scraped_at` | `YYYY-MM-DD HH:MM:SS` | Time of the request, Taiwan time (`Asia/Taipei`) |
| 3 | `platform` | text | `momo`, `pchome` or `coupang` |
| 4 | `product_id` | text | From the product table |
| 5 | `platform_item_id` | text | The platform's own ID |
| 6 | `original_price` | integer | The crossed-out 原價 / 市價. `NA` if none shown |
| 7 | `sale_price` | integer | The headline price, before any conditional reduction |
| 8 | `extra_price` | integer | The lowest further price shown with a condition (member, coupon, time-limited, card). `NA` if none |
| 9 | `extra_price_label` | text | The label next to `extra_price`, copied exactly |
| 10 | `shown_discount_pct` | number | The "% off" badge as displayed: `-23%` → `23`. `NA` if none |
| 11 | `promo_tag` | text | Sale or campaign labels, copied exactly. Several → joined with ` \| ` |
| 12 | `coupon_note` | text | Coupon or card wording, copied exactly |
| 13 | `seller_type` | text | `platform` (sold by the platform itself) or `marketplace` (third-party seller). `NA` if unclear |
| 14 | `in_stock` | `TRUE`/`FALSE` | `NA` if the page could not be read |
| 15 | `http_status` | integer | `200`, `403`, `404`, `429`... `NA` if no response |
| 16 | `source` | text | `scraper` or `hand_log` |

### 6.2 Value rules

- **Prices** are whole NT$ numbers: strip `$`, `NT$`, `元` and commas. `4,490` → `4490`.
- **Text** is copied as shown, in Chinese, with surrounding spaces trimmed.
- **Missing** is written as `NA`. Not `0`, not blank, not `-`.
- **File format:** UTF-8, comma-separated, one header row.

### 6.3 Where each column comes from

**(check)** = not yet confirmed on a real page. Whoever builds that scraper confirms it and
updates this table.

| Column | PChome (JSON product feed) | momo (product page HTML) | Coupang (product page) |
|---|---|---|---|
| `original_price` | `Price.M` if it differs from `Price.P`, else `NA` | 市售價 / 市價 / 原價 in the main price block; verified 2026-10-18 | Crossed-out 原價 if shown **(check)** |
| `sale_price` | `Price.P` | Explicit 促銷價 / 售價, including the secondary crossed-out 促銷價 when a further conditional price is the headline; verified 2026-10-18 | Main price |
| `extra_price` | `NA` unless a member or coupon price appears | Explicit conditional price such as 限時折後價; keep its label. JSON-LD can hold this amount, so do not use it as ordinary sale_price; verified 2026-10-18 | Member / coupon / card price **(check)** |
| `seller_type` | `platform` unless shown otherwise | `platform` unless a third-party shop is shown **(check)** | Rocket badge → `platform`; seller name → `marketplace` **(check)** |
| `in_stock` | `Qty > 0` and `SaleStatus` | No sold-out notice | No sold-out notice |

Known endpoints (tested 2026-10-05):

- **PChome:** product feed
  `https://ecapi-cdn.pchome.com.tw/ecshop/prodapi/v2/prod/button&id=<ID>&fields=Seq,Id,Price,Qty,ButtonType,SaleStatus`.
  The main website returns 429 to scripts, so use the feed.
- **momo:** product page `https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=<i_code>`.
  Prices are in the HTML. `/api/` and `/ajax/` are disallowed by robots.txt; don't use them.

Implementation check (2026-10-18): the current recorder requests the public canonical
`https://www.momoshop.com.tw/product/<i_code>` directly. Current price containers use
`data-testid="price-main-container"`, `price-primary-row` and `price-strike-row`.
The label, not whether the amount is crossed out, determines the field: Ferrero showed
市售價 299, 促銷價 275 and 限時折後價 233. See `momo-verification.md`.
The initial `data/products.csv` is a seven-product momo-only pilot; broader study eligibility
and the remaining products stay under review. The seller default remains provisional **(check)**.

---

## 7. Non-functional requirements

| ID | Requirement |
|---|---|
| **NFR-1 Pace** | At least 5 seconds between requests to the same site. |
| **NFR-2 Identity** | A user agent naming the study and a contact address, e.g. `PBA-Double11-study (NTHU ISS4066; contact: <email>)`. |
| **NFR-3 robots.txt** | Follow each site's robots.txt. |
| **NFR-4 No circumvention** | If a site returns 403 or a challenge page, log it and stop. No proxies, no disguised browsers, no workarounds. Coupang is accessed only through the access Coupang granted. |
| **NFR-5 Language** | R, with `httr2`, `rvest` and `jsonlite` (the course's language; the repo must hold all project code). |
| **NFR-6 Secrets** | Tokens and passwords go in `.Renviron`, never in git. |
| **NFR-7 Reliability** | One product failing never stops the run (see FR-3). |

## 8. Schedule of runs

| Period | Runs |
|---|---|
| Oct 19 → Nov 9 | Once a day, around **10:00** Taiwan time |
| **Nov 10, 11, 12** | Three times a day: 10:00, 18:00, 23:00 (flash sales) |
| Nov 13 → Nov 25 | Once a day, 10:00 |

A missed run is made up as soon as possible; `scraped_at` records the real time. Never back-fill
a missed day by copying another day's values.

## 9. BigGo transcription format: `data/biggo/price_changes.csv`

Type in **change points only**, one row per price change. R turns these into daily prices.

| Column | Type | Content |
|---|---|---|
| `product_id` | text | From the product table |
| `platform` | text | Platform of the BigGo listing: `momo`, `pchome`, `coupang` |
| `biggo_url` | text | The listing transcribed |
| `changed_at` | `YYYY-MM-DD HH:MM` | Timestamp as BigGo shows it |
| `price` | integer | Price after the change, NT$ |
| `entered_by` | text | Your first name |
| `entered_on` | `YYYY-MM-DD` | Date you typed it |
| `note` | text | Anything odd (gap in history, seller changed). Otherwise `NA` |

- **Period:** Oct 1 to Nov 25, in 2025 and in 2026. 2025 is typed now; 2026 after collection
  ends on Nov 25.
- Include the last change **before** the period starts, so the first day's price is known.
- About 10% of listings are typed a second time by someone else as a check; differences are
  resolved and noted.

---

## 10. Deliverables and deadlines

| # | Deliverable | Owner | Due |
|---|---|---|---|
| D1 | 3 test products per platform in the product table | | Wed Oct 14 |
| D2 | Full product table, ~100 products | | Sat Oct 17 |
| D3 | PChome scraper passing section 11 | | Sat Oct 17 |
| D4 | momo scraper passing section 11 | | Sat Oct 17 |
| D5 | Coupang scraper passing section 11 | | Sat Oct 17 |
| D6 | Daily runs live on all three platforms | all | **Mon Oct 19** |
| D7 | 2025 BigGo history | | Sun Oct 25 (Milestone 2) |
| D8 | Extra runs on Nov 10 to 12 | all | Thu Nov 12 |
| D9 | Collection stops; last snapshots committed | all | Wed Nov 25 |
| D10 | 2026 BigGo history | | Sun Nov 29 |

## 11. Acceptance criteria

A scraper is ready to go live when all of these hold:

- [ ] Runs end to end with the single command in FR-7.
- [ ] Tested on at least 3 products from the product table.
- [ ] The CSV header matches section 6.1 exactly, names and order.
- [ ] Prices are whole numbers; Chinese text reads correctly when the file is opened in R with
      `read.csv(file, fileEncoding = "UTF-8")`.
- [ ] Missing values are `NA`.
- [ ] One deliberately wrong product ID produces a row with an `http_status` and `NA` prices,
      and the run continues.
- [ ] Running twice on the same day appends rows without repeating the header.
- [ ] Raw pages are saved as `.gz` under `raw/`, and `raw/` is in `.gitignore`.
- [ ] Prices for 3 products match what the page shows in a browser.
- [ ] The **(check)** cells in section 6.3 for that platform are confirmed and updated.

## 12. Open questions

| # | Question | Who answers | Status |
|---|---|---|---|
| Q1 | Does momo show a crossed-out 市價 on product pages? | momo owner | Confirmed 2026-10-18: inspected public pages show 市售價. A crossed-out 促銷價 can also appear separately from 市售價; see section 6.3. |
| Q2 | Does Coupang show a crossed-out 原價? What second prices appear? | Coupang owner | Open |
| Q3 | How do momo and Coupang show third-party sellers? | Platform owners | Open |
| Q4 | Does BigGo's history show the 原價 as well as the price? How often does it check prices? | BigGo transcribers | Open |
| Q5 | Do the scrapers run on GitHub Actions or on a laptop with Task Scheduler? | Team | Open |
