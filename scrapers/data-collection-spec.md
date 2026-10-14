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

1. **Scrapers for momo, PChome and Coupang**: one R script per platform, in that platform's
   folder under `scrapers/`, that writes one row per product per run in the format in section 7.
2. **A GitHub Actions workflow** that runs all three scrapers on the schedule in section 9, from
   Oct 19 to Nov 25, with extra runs around 11.11.
3. **BigGo price history transcribed** into the format in section 11.

Owners are in section 12 (assigned at the Oct 12 kickoff).

## 3. Scope

**In scope**

- momo, PChome and Coupang product pages, for the products in the product table (section 6).
- BigGo price history for the same products.

**Out of scope**

- Shopee (excluded by design: marketplace structure and anti-bot protection).
- Any calculation: real discount, 30-day low, percentages. The analysis does this later in R.
- Anything behind a login, and any personal data.
- Committing output to the repo. The scrapers write files locally (git ignores them); where
  they are stored long term is open question Q6.

## 4. Conventions

- **Project root.** All paths in this document are relative to the root of this repo, which
  the scrapers are run from. Each platform's code, output and raw pages live in its own folder,
  `scrapers/<platform>/`.
- **Time.** Every date and time is Taiwan time (`Asia/Taipei`, UTC+8, no daylight saving). The
  GitHub runner's clock is UTC, so the code always converts explicitly and never relies on the
  system time zone.
- **Run.** One execution of one platform's scraper. A run has a **run date** (`YYYY-MM-DD`) and
  a **run time** (`HHMM`), both taken once, in Taiwan time, when the run starts. Every row and
  file of that run uses them.

---

## 5. Functional requirements

| ID | Requirement |
|---|---|
| **FR-1** | The scraper reads its product list from `products/products.csv` (section 6). An optional first command-line argument gives a different product table, for testing. No product IDs or URLs are hard-coded. |
| **FR-2** | For every product that has a link on that platform (section 6.2), it writes exactly one row per run, with the columns in section 7, in that order. |
| **FR-3** | A product that fails still gets a row: prices `NA`, the reason in `fetch_status`, the HTTP status in `http_status`. A failed row and a missing row must look different. Failure handling is in section 8. |
| **FR-4** | Each run writes a new file: `scrapers/<platform>/output/<platform>_<run date>_<run time>.csv`, e.g. `scrapers/momo/output/momo_2026-11-11_1807.csv`. If that file already exists, the scraper stops with an error before sending any request. Files are never appended to or overwritten. |
| **FR-5** | Every response body received, whatever its status, is saved gzip-compressed to `scrapers/<platform>/raw/<run date>_<run time>/<platform_item_id>.html.gz` (`.json.gz` for PChome), so a parsing bug can be fixed later by re-parsing old pages. No response, no file. |
| **FR-6** | The scraper copies what the page shows. It never computes discounts, never fills a missing value from another run, and never translates or rewords labels. The only change it makes to text is the whitespace rule in section 7.2. |
| **FR-7** | One command runs a platform: `Rscript scrapers/<platform>/scrape_<platform>.R` from the project root, where `<platform>` is `momo`, `pchome` or `coupang`. The script creates its `output/` and `raw/` folders if they are missing. |
| **FR-8** | At the end of a run it prints one summary line: platform, products attempted, count per `fetch_status` value, output file. Example: `momo: 98 products | ok 95, http_error 2, parse_failure 1 | scrapers/momo/output/momo_2026-10-19_1007.csv` |
| **FR-9** | Exit code: `1` if no product ended `ok`, or if the run could not start (section 6.3). Otherwise `0`, even when some products failed. The output file is written before exiting either way. A non-zero exit is what makes the GitHub run show as failed and send the failure email. |

---

## 6. Input: the product table `products/products.csv`

Alicia and Audrey build this table by hand. They paste product **links**, not IDs: each
scraper takes the ID it needs out of the link.

### 6.1 Columns

One row per product. The same physical product on several platforms is **one row** with several
links; that is how platforms get matched.

| Column | Example | Notes |
|---|---|---|
| `product_id` | `3C-001` | Category code + 3 digits. Unique. Never reused or renumbered |
| `brand` | `Apple` | |
| `model` | `AirPods 4 (ANC)` | Exact variant: size, colour, pack count |
| `category` | `3C` | `3C` electronics · `APPL` small appliances · `BEAU` beauty · `FOOD` snacks and drinks · `HOME` home and daily goods |
| `momo_url` | | momo product page link. Empty if not sold on momo |
| `pchome_url` | | PChome product page link. Empty if not sold on PChome |
| `coupang_url` | | Coupang product page link. Empty if not sold on Coupang |
| `biggo_url_momo`, `biggo_url_pchome`, `biggo_url_coupang` | | BigGo listing to transcribe |

The file is UTF-8 with one header row. Empty cells mean "not on that platform". Links are
pasted from a browser's address bar, so they may carry extra tracking parameters; the scrapers
must cope with that.

### 6.2 Which products a scraper takes

| Platform | Product is included when | `platform_item_id` | URL requested |
|---|---|---|---|
| momo | `momo_url` is not empty | The `i_code` value in the link | Built from the ID (section 7.3) |
| PChome | `pchome_url` is not empty | The product ID in the link (the part after `/prod/`; see 7.3 on its exact form) | Built from the ID (section 7.3) |
| Coupang | `coupang_url` is not empty | The `itemId` value in the link | `coupang_url` as stored |

Products are requested in the order they appear in the file.

### 6.3 Bad input

- **The run cannot start** (exit 1, no requests, no output file) if the product table is
  missing, has a column missing from 6.1, or `SCRAPER_CONTACT` is not set (NFR-2).
- **A single product is bad** if its `product_id` appears more than once, or the ID cannot be
  found in its link. It gets a row with `fetch_status` = `bad_input` and no request is sent.
  Every other product runs normally. Tell Alicia and Audrey which rows were bad.

### 6.4 Selection rules (for whoever fills the table)

Target: about 100 products, about 20 per category, on as many platforms as possible.

Each product must:
- be sold on at least 2 of momo, PChome and Coupang, as the same variant (size, colour, pack count);
- be sold by the platform itself, not a third-party shop;
- have BigGo price history back to at least October 2025;
- be something students commonly buy.

---

## 7. Output: snapshot format

### 7.1 Columns (exact names, this order)

| # | Column | Type | Content |
|---|---|---|---|
| 1 | `date` | `YYYY-MM-DD` | Run date |
| 2 | `scraped_at` | `YYYY-MM-DD HH:MM:SS` | Time this product's request was sent, Taiwan time. `NA` if no request was sent |
| 3 | `platform` | text | `momo`, `pchome` or `coupang` |
| 4 | `product_id` | text | From the product table |
| 5 | `platform_item_id` | text | See 6.2. `NA` if it could not be found |
| 6 | `original_price` | integer | The crossed-out 原價 / 市價. `NA` if none shown |
| 7 | `sale_price` | integer | The headline price, before any conditional reduction |
| 8 | `extra_price` | integer | The lowest further price shown with a condition (member, coupon, time-limited, card). `NA` if none |
| 9 | `extra_price_label` | text | The label next to `extra_price`. `NA` if none |
| 10 | `shown_discount_pct` | number | A "% off" badge as displayed: `-23%` → `23`. `NA` if none (see 7.2 for 折) |
| 11 | `promo_tag` | text | Sale or campaign labels. Several → joined with ` \| ` |
| 12 | `coupon_note` | text | Coupon or card wording |
| 13 | `seller_type` | text | `platform` (sold by the platform itself) or `marketplace` (third-party seller). `NA` if unclear |
| 14 | `in_stock` | `TRUE`/`FALSE` | `NA` unless `fetch_status` is `ok` |
| 15 | `http_status` | integer | Status of the last response for this product: `200`, `403`, `404`, `429`... `NA` if no response |
| 16 | `source` | text | Always `scraper`. (`hand_log` is reserved for rows a person types in from a browser; not part of the scraper build) |
| 17 | `fetch_status` | text | One of the values in section 8.1 |

### 7.2 Value rules

- **Prices** are whole NT$ numbers: strip `$`, `NT$`, `元` and commas. `4,490` → `4490`.
- **Text** is copied as shown, in Chinese. Leading and trailing whitespace is trimmed, and
  newlines or runs of whitespace inside are replaced by one space. Nothing else changes.
- **Several promo tags** are joined in the order they appear on the page; exact duplicates are
  dropped.
- **折 badges** (`7折`, `85折`) are not converted to a percentage. The badge goes into
  `promo_tag` as displayed and `shown_discount_pct` stays `NA`.
- **Missing** is written as `NA`. Not `0`, not blank, not `-`.
- **File format:** UTF-8, comma-separated, one header row, text quoted where needed. Base R's
  `write.csv(x, file, row.names = FALSE, na = "NA", fileEncoding = "UTF-8")` meets this.

### 7.3 Where each column comes from

**(check)** = not yet confirmed on a real page. Whoever builds that scraper confirms it and
updates this table.

| Column | PChome (JSON product feed) | momo (product page HTML) | Coupang (product page HTML) |
|---|---|---|---|
| `original_price` | `Price.M` if it differs from `Price.P`, else `NA` | Crossed-out 市價 if shown **(check)** | Crossed-out 原價 if shown **(check)** |
| `sale_price` | `Price.P` | 促銷價 | Main price **(check)** |
| `extra_price` | Always `NA` (the feed carries no conditional prices) | 限時折後價 (the JSON-LD `price` also holds this) | Member / coupon / card price **(check)** |
| `shown_discount_pct`, `promo_tag`, `coupon_note` | Always `NA` | From the page **(check)** | From the page **(check)** |
| `seller_type` | `platform` | `platform` unless a third-party shop is shown **(check)** | Rocket badge → `platform`; seller name → `marketplace` **(check)** |
| `in_stock` | `TRUE` if `Qty > 0`, else `FALSE` | `FALSE` if a sold-out notice is shown, else `TRUE` **(check)** | `FALSE` if a sold-out notice is shown, else `TRUE` **(check)** |
| Challenge-page marker (section 8.1) | n/a (JSON) | **(check)** | **(check)** |

Endpoints:

- **PChome** (tested 2026-10-05): product feed
  `https://ecapi-cdn.pchome.com.tw/ecshop/prodapi/v2/prod/button&id=<platform_item_id>&fields=Seq,Id,Price,Qty,ButtonType,SaleStatus`.
  The main website returns 429 to scripts, so use the feed. Whether the ID exactly as it
  appears in a `24h.pchome.com.tw/prod/...` link works in the feed, or needs a suffix such as
  `-000`, is **(check)**. robots.txt (checked 2026-10-13): the feed host has none (404);
  `24h.pchome.com.tw` does not disallow `/prod/`.
- **momo** (tested 2026-10-05): product page
  `https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=<platform_item_id>`. Prices are in
  the HTML. robots.txt (checked 2026-10-13) allows `GoodsDetail.jsp`, disallows `/api/` and
  `/ajax/`, and also disallows URLs carrying the tracking parameters `utm_`, `osm=` and
  `recomd_id=`. Links pasted from a browser often carry these, which is why the scraper builds
  its own URL from the `i_code` and never requests the pasted link.
- **Coupang:** the product page at `coupang_url`, requested exactly as stored in the product
  table. Prices are read from the HTML; check whether it carries JSON-LD like momo's, and prefer
  it when it does. **(check)** robots.txt (checked 2026-10-13) returns 403 to an ordinary
  request, like the rest of the site, so expect to need the workarounds in section 8.2.

---

## 8. Failures, retries and blocks

### 8.1 `fetch_status` values

| Value | Meaning | Prices | `http_status` |
|---|---|---|---|
| `ok` | Page read. The sale price was found, or the page shows a sold-out or removed notice (`in_stock` = `FALSE`, prices as shown or `NA`) | As shown | `200` |
| `parse_failure` | Status 200, not a challenge page, but neither a sale price nor a sold-out notice was found | `NA` | `200` |
| `http_error` | 404, any other 4xx except 403 and 429, or a 5xx still failing after the retry | `NA` | The status |
| `timeout` | No response (timeout or connection error) after the retry | `NA` | `NA` |
| `blocked` | 403, a challenge page (CAPTCHA, "Access Denied", JavaScript check; treated as 403 even when the status is 200), or 429 still returned after every workaround in 8.2 was tried | `NA` | The status |
| `bad_input` | Product table row is invalid (6.3); not requested | `NA` | `NA` |

### 8.2 Rules

- **Timeout:** 30 seconds per request.
- **One retry** for 429, 5xx, timeout or connection error, sent 60 seconds after the failure.
  No retry for anything else.
- **On a block, get around it.** A 403, challenge page or repeated 429 is not a reason to stop.
  Do whatever gets the page: back off longer, change the user agent and headers, carry cookies
  from earlier responses, switch to a headless or real browser, or route through a different IP
  or proxy. A product is marked `blocked` only when nothing worked, and the run moves on to the
  next product. If a platform starts blocking, improve the scraper so the next run gets through.
- **Everything continues.** `parse_failure`, `http_error`, `timeout`, `blocked` and `bad_input`
  affect only that product (NFR-7).

---

## 9. Running on GitHub Actions

### 9.1 Schedule

| Period (Taiwan time) | Runs | Cron (UTC) |
|---|---|---|
| Oct 19 → Nov 25 | Once a day, 10:07 | `7 2 * * *` |
| **Nov 10, 11, 12** | Two extra runs, 18:07 and 23:07 (flash sales) | `7 10 10-12 11 *` and `7 15 10-12 11 *` |

The runs are seven minutes past the hour because GitHub delays or drops more scheduled runs
on the hour. Scheduled runs can still start late; `scraped_at` records the real time.

### 9.2 Workflow requirements

| ID | Requirement |
|---|---|
| **WF-1** | One workflow file, `.github/workflows/scrape.yml`, with the three cron entries above and a manual trigger (`workflow_dispatch`). |
| **WF-2** | One job per platform (a matrix over `momo`, `pchome`, `coupang`, with `fail-fast: false`), so one platform failing does not cancel the others. Jobs may run in parallel; the pace rule (NFR-1) is per site. |
| **WF-3** | Scheduled runs outside Oct 19 – Nov 25 (Taiwan date) do nothing and end green. Manual runs always run, for testing and make-ups. |
| **WF-4** | R 4.6.1 via `r-lib/actions/setup-r`, packages via `r-lib/actions/setup-r-dependencies` (cached binaries, not source builds). |
| **WF-5** | `SCRAPER_CONTACT` comes from a repository secret of the same name. |
| **WF-6** | After the scraper step, whatever its exit code, the job uploads that run's output file and `raw/` folder from `scrapers/<platform>/` as one workflow artifact named `<platform>_<run date>_<run time>`, kept 90 days. This is the interim storage until Q6 is answered. |
| **WF-7** | Job timeout 45 minutes. A full run is about 100 products × 5 s ≈ 9 minutes, plus retries. |

### 9.3 Watching the runs

GitHub emails scheduled-run failures to whoever last edited the cron lines, so that person
watches. A failed or missing run is made up with a manual run as soon as it is noticed. Never
back-fill a missed run by copying another run's values.

---

## 10. Non-functional requirements

| ID | Requirement |
|---|---|
| **NFR-1 Pace** | 5 seconds between requests to the same site by default, retries included. Change it if that helps get past a block. |
| **NFR-2 Identity** | User agent `PBA-Double11-study (NTHU ISS4066; contact: <SCRAPER_CONTACT>)`, where `SCRAPER_CONTACT` is an environment variable holding the team's contact email: in `.Renviron` at the project root locally, a repository secret on GitHub (WF-5). This is the default; it may be changed to get past a block (section 8.2). |
| **NFR-3 robots.txt** | The builder checks each site's robots.txt against the URLs the scraper requests, before going live, and records the date checked in 7.3. The scraper does not parse robots.txt at run time. |
| **NFR-4 Getting past blocks** | Blocks are worked around, not accepted (section 8.2). Proxies, headless or real browsers, rotating user agents and any other workaround are all allowed. |
| **NFR-5 Language** | R 4.6.1, with `httr2`, `rvest` and `jsonlite` (the course's language), plus `chromote` (headless Chrome) for pages that block plain requests. CSV writing and gzip use base R. Any other package that helps is allowed; list it here when you add it. |
| **NFR-6 Secrets** | Tokens, passwords and the contact address go in `.Renviron` or GitHub secrets, never in git. `.Renviron`, `output/` and `raw/` are listed in `.gitignore`. |
| **NFR-7 Reliability** | One product failing never stops the run. |

---

## 11. BigGo transcription format: `biggo/price_changes.csv`

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

## 12. Deliverables and deadlines

| # | Deliverable | Owner | Due |
|---|---|---|---|
| D1 | Scraper tested on 3 products of the owner's choice | Each scraper owner, for their platform | Wed Oct 14 |
| D2 | Full product table, ~100 products | Alicia, Audrey | Sat Oct 17 |
| D3 | PChome scraper passing section 13 | Albert | Sat Oct 17 |
| D4 | momo scraper passing section 13 | Jordan | Sat Oct 17 |
| D5 | Coupang scraper passing section 13 | Marvin | Sat Oct 17 |
| D6 | Workflow (section 9) passing section 13, manual run green on all three platforms | Marvin | Sun Oct 18 |
| D7 | First scheduled run on all three platforms | all | **Mon Oct 19** |
| D8 | 2025 BigGo history | | Sun Oct 25 (Milestone 2) |
| D9 | Extra runs on Nov 10 to 12 | all | Thu Nov 12 |
| D10 | Collection stops; workflow disabled; every run's output saved to the Q6 location | all | Wed Nov 25 |
| D11 | 2026 BigGo history | | Sun Nov 29 |

## 13. Acceptance criteria

**A scraper** is ready to go live when all of these hold:

- [ ] Runs end to end with the single command in FR-7, locally, with `SCRAPER_CONTACT` set.
- [ ] Tested on at least 3 real products.
- [ ] The CSV header matches section 7.1 exactly, names and order.
- [ ] Prices are whole numbers; Chinese text reads correctly when the file is opened in R with
      `read.csv(file, fileEncoding = "UTF-8")`.
- [ ] Missing values are `NA`.
- [ ] A test product table (FR-1 argument) with one wrong link and one `bad_input` row gives
      rows with `http_error` (or `parse_failure`) and `bad_input`, and the run continues to the
      next product.
- [ ] Links with extra tracking parameters are handled (6.1).
- [ ] Without `SCRAPER_CONTACT` set, it exits 1 without sending a request.
- [ ] A second run in the same minute stops with an error and leaves the first file untouched.
- [ ] Raw responses are saved as `.gz` under `scrapers/<platform>/raw/`, and git ignores them.
- [ ] Prices for 3 products match what the page shows in a browser.
- [ ] The **(check)** cells in section 7.3 for that platform are confirmed and updated, and the
      robots.txt check date is recorded.

**The workflow** is ready when:

- [ ] A manual run produces one artifact per platform, each holding the CSV and raw pages.
- [ ] Rows in that CSV show Taiwan time, not UTC.
- [ ] One platform's job failing leaves the other two to finish.

## 14. Open questions

| # | Question | Who answers | Status |
|---|---|---|---|
| Q1 | Does momo show a crossed-out 市價 on product pages? | momo owner | Open |
| Q2 | Does Coupang show a crossed-out 原價? What second prices appear? | Coupang owner | Open |
| Q3 | How do momo and Coupang show third-party sellers? | Platform owners | Open |
| Q4 | Does BigGo's history show the 原價 as well as the price? How often does it check prices? | BigGo transcribers | Open |
| Q5 | Do the scrapers run on GitHub Actions or on a laptop with Task Scheduler? | Team | **Closed 2026-10-13: GitHub Actions** (section 9) |
| Q6 | Where are snapshots and raw pages kept long term? (The scrapers and workflow live in this repo.) Until decided, outputs live as 90-day workflow artifacts (WF-6), the earliest of which expire around Jan 17; decide before the final report (Dec 20). The repo is public (checked 2026-10-13), so artifact storage has no quota; if it is made private, GitHub Free's 500 MB artifact quota applies and the raw pages may approach it. | Team | Open |
