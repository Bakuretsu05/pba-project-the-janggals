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

1. **Scrapers for momo and PChome**: one R script per platform, in that platform's
   folder under `scrapers/`, that writes one row per product per run in the format in section 7.
   **Coupang was dropped from the daily snapshots on 2026-10-20**; its prices come from BigGo
   history only (section 11). The Coupang scraper in `scrapers/coupang/` is kept for reference
   and no longer runs (Q7).
2. **A GitHub Actions workflow** that runs the scrapers on the schedule in section 9, from
   Oct 19 to Nov 25, with extra runs around 11.11.
3. **BigGo price history collected** into the format in section 11.

Owners are in section 12 (assigned at the Oct 12 kickoff).

## 3. Scope

**In scope**

- momo and PChome product pages, for the products in the product table (section 6).
- BigGo price history for the same products, on momo, PChome and Coupang.

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
| **FR-5** | Every response body received, whatever its status, is saved gzip-compressed to `scrapers/<platform>/raw/<run date>_<run time>/<platform_item_id>.html.gz`, so a parsing bug can be fixed later by re-parsing old pages. PChome now saves product HTML, not feed JSON (team decision 2026-10-16). No response, no file. |
| **FR-6** | The scraper copies what the page shows. It never computes discounts, never fills a missing value from another run, and never translates or rewords labels. The only change it makes to text is the whitespace rule in section 7.2. |
| **FR-7** | One command runs a platform: `Rscript scrapers/<platform>/scrape_<platform>.R` from the project root, where `<platform>` is `momo` or `pchome`. The script creates its `output/` and `raw/` folders if they are missing. |
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
| `coupang_url` | | Coupang product page link. Empty if not sold on Coupang. Not scraped since 2026-10-20 |
| `biggo_url_momo`, `biggo_url_pchome`, `biggo_url_coupang` | | BigGo search page for that platform. It can show several listings, so the history is looked up by item ID instead (`biggo/README.md`) |

The file is UTF-8 with one header row. Empty cells mean "not on that platform". Links are
pasted from a browser's address bar, so they may carry extra tracking parameters; the scrapers
must cope with that.

### 6.2 Which products a scraper takes

| Platform | Product is included when | `platform_item_id` | URL requested |
|---|---|---|---|
| momo | `momo_url` is not empty | The `i_code` value in the link, or the ID in a `/product/<ID>` link | Built from the ID (section 7.3) |
| PChome | `pchome_url` is not empty | The product ID in the link (the part after `/prod/`; see 7.3 on its exact form) | Built from the ID (section 7.3) |
| Coupang (retired 2026-10-20) | `coupang_url` is not empty | The `itemId` value in the link | `coupang_url` as stored |

Products are requested in the order they appear in the file.

### 6.3 Bad input

- **The run cannot start** (exit 1, no requests, no output file) if the product table is
  missing, has a column missing from 6.1, or `SCRAPER_CONTACT` is not set (NFR-2).
- **A single product is bad** if its `product_id` appears more than once, or the ID cannot be
  found in its link. It gets a row with `fetch_status` = `bad_input` and no request is sent.
  Every other product runs normally. Tell Alicia and Audrey which rows were bad.

### 6.4 Selection rules (for whoever fills the table)

Target: 150 products, 30 per category (raised from about 100 on 2026-10-20, when Coupang was dropped from the daily snapshots and kept for BigGo history only).

Each product must:
- be sold on both momo and PChome, as the same variant (size, colour, pack count); a Coupang link is optional;
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
| 3 | `platform` | text | `momo` or `pchome` (`coupang` in the Coupang runs of Oct 19 and 20) |
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
- **Comparing platforms:** the sites label the same discount differently, so it can land in
  different columns. On 2026-10-20 BEAU-007 was 800 on both: momo showed 促銷價 1600 with
  限時折後價 800 (`sale_price` 1600, `extra_price` 800), PChome showed 網路價 800
  (`sale_price` 800). The analysis compares the lowest price shown, not `sale_price` alone.
- **File format:** UTF-8, comma-separated, one header row, text quoted where needed. Base R's
  `write.csv(x, file, row.names = FALSE, na = "NA", fileEncoding = "UTF-8")` meets this.

### 7.3 Where each column comes from

**(check)** = not yet confirmed on a real page. Whoever builds that scraper confirms it and
updates this table. The Coupang column and endpoint describe the retired Coupang scraper.

| Column | PChome (customer-visible product HTML) | momo (product page HTML) | Coupang (product page HTML) |
|---|---|---|---|
| `original_price` | Visible crossed-out price in the product price block (`del`/`s`, explicit line-through, or visually verified `.c-prodPrice__originalPrice` class). Preserve it even if equal to the pre-condition selling price. Never substitute API `Price.M` | Explicit 市售價 / 市價 / 原價 in the main price block (shown on 70 of 92 pages, 2026-10-19) | Crossed-out price: the JSON-LD `StrikethroughPrice`, else the struck price in `.price-container`. Per Coupang, the supplier's suggested or official-channel price, else the item's highest Coupang price in 90 days |
| `sale_price` | Displayed pre-condition selling price; in the verified 折扣價 / 網路價 layout, the displayed 網路價. Unknown conditional baselines give `parse_failure` | 促銷價 | Headline price (JSON-LD `offers.price`). If a line under it marks the headline as conditional (`$198 首購折扣價`, or `$65 折扣後價格 · 折扣剩下8小時` for a time-limited discount), the price without the reduction instead: the crossed-out price on that line if it has one (`$490`), else the main crossed-out price, provided headline + reduction = that price; otherwise `NA` and `parse_failure` |
| `extra_price` | Lowest verified conditional price linked to displayed condition wording; copy that wording to `extra_price_label`. Unverified amounts/labels stay `NA` | 限時折後價 (the JSON-LD `price` also holds this) | Lowest of: a headline marked conditional (label e.g. `首購折扣價`, first purchase, or `折扣後價格`, time-limited) and card prices under 刷卡優惠 (label e.g. `王道卡 特惠價`) |
| `shown_discount_pct`, `promo_tag`, `coupon_note` | Copy product price/discount percentage badges, campaign/promotion text, and visible coupon/card wording from the main product area. Do not infer % from amounts or cashback; 折 stays text. The coloured slogan line above the product name is product copy and is not read (from 2026-10-21) Interactive/image-only content has incomplete coverage, recorded in a separate verification audit | `promo_tag`: each row of the campaign block under the product name, the dated campaign link then its condition (`10/01~10/31 ★AirPods十在優惠 \| 滿1件折1102元`). `coupon_note`: 折價券, 刷卡 and 回饋 wording in the purchase column. No % badge on 92 pages (2026-10-19), so `shown_discount_pct` is `NA` so far | Product pages show `N折`, never %, so `shown_discount_pct` is `NA` and the badge goes to `promo_tag`. `coupon_note`: the conditional line, `.conditional-benefits`, 刷卡優惠 and 銀行回饋 entries. 11.11 campaign labels not seen yet |
| `seller_type` | `platform` (24h product pages are sold by PChome itself) | `platform` unless the purchase column names a third-party seller (第三方賣家, 店家名稱, a `/3p/` link). None seen on 93 pages (2026-10-19) | `賣家：<name>` (`.seller-info`) → `marketplace`; else the `ROCKET` badge in the price block → `platform` |
| `in_stock` | Enabled purchase buttons → `TRUE`; explicit sold-out/removed notice → `FALSE`; otherwise `TRUE` when a selling price is shown | `FALSE` if a sold-out notice (已售完, 補貨中) is shown or every option's JSON-LD `availability` is out of stock, else `TRUE`; mixed option stock → `NA`. No sold-out page seen yet **(check)**. A removed item or wrong link gets a generic 網頁無法顯示 page that lists 商品目前無展售 and 網頁不存在 as possible causes: `parse_failure` | JSON-LD `offers.availability` (`InStock` → `TRUE`); without JSON-LD, `FALSE` if 已售完, 暫時缺貨 or similar is shown. Checked 2026-10-19: two 暫時缺貨 pages had `OutOfStock`. A wrong link and a delisted item get the same HTTP 200 page, 找不到商品: `parse_failure` |
| Challenge-page marker (section 8.1) | Only on a page without the product block: `sec-if-cpt-container`, `cf-chl-`, `challenge-platform`, or visible text Access Denied, CAPTCHA, verify you are human, 網頁載入中, JavaScript required/check. A page with the product block is never a challenge | Only on a page without the price block and 品號: Access Denied, Just a moment, `sec-if-cpt-container`, `cf-chl-`, `challenge-platform`, `g-recaptcha`, 驗證您是人類, 安全驗證. None seen on 93 pages from a home connection (2026-10-19) **(check)** from GitHub | Akamai: `Access Denied`, or `sec-if-cpt-container` (JavaScript check that reloads itself); Coupang: `id="error403"` (你沒有權限存取此頁面) |

Endpoints:

- **PChome** (team decision and verification 2026-10-16, Albert): the customer-visible product
  page `https://24h.pchome.com.tw/prod/<platform_item_id>`, via identified httr2 requests.
  Three real products returned HTTP 200 with server-rendered price/promotion text. Product
  identity and the main product/price blocks are checked before extracting values. No API
  price or JSON-LD fallback is used. Base product IDs work without `-000`; a suffixed variant
  is collected only if the page identifies that exact requested variant. robots.txt was
  rechecked on 2026-10-16 and allows ordinary `/prod/` pages. The asset host disallows all
  automated paths; no direct CSS scraping request was made. Price strike-through styling was checked
  visually in the browser on the three test products.
  The soy milk regression `DBAB13-A900K0RK8` has displayed baseline 285, crossed-out 285 and
  conditional 275 (`限時活動 10/14 - 10/31 任選1件$275`); its internal feed reference 336 is
  excluded. The equal crossed-out and sale prices on the M331 page are also preserved.
  Interactive coupon/payment/member details and image-only promotion labels are not fully
  covered. Every run writes a separate `raw/<stamp>/verification.csv` and prints a warning;
  `ok` certifies the selling price/sold-out criterion, not complete offer coverage. Unsupported
  fields remain `NA`. See `pchome/README.md` for mappings and limitations. Blocks follow
  section 8.2: after the one retry, back off and request again with a browser user agent, then
  load the page in a fresh headless Chrome (`chromote`); after three products in a row end
  blocked, later products get one request each. On 2026-10-18 (Marvin) a plain httr2 request
  got HTTP 200 while headless Chrome got 429, so the browser user agent is the useful
  workaround and headless Chrome is the last resort. Raw files: the body the row was read from
  is `<platform_item_id>.html.gz`; earlier attempts are `<platform_item_id>__attempt<n>.html.gz`.
- **momo** (rechecked 2026-10-19, Jordan and Marvin): product page
  `https://www.momoshop.com.tw/product/<platform_item_id>`, built from the ID whether the link
  is a `/product/<ID>` or a `GoodsDetail.jsp?i_code=<ID>` link. Prices are in the HTML.
  robots.txt (checked 2026-10-18) allows `/product/` and `GoodsDetail.jsp`, disallows `/api/`
  and `/ajax/`, and also disallows URLs carrying the tracking parameters `utm_`, `osm=` and
  `recomd_id=`. Links pasted from a browser often carry these, which is why the scraper builds
  its own URL from the ID and never requests the pasted link. In the price block, 市售價 is
  `original_price`, 促銷價 is `sale_price` even when struck through beside a further offer, and
  限時折後價 is `extra_price` (Ferrero: 299 / 275 / 233). The JSON-LD `price` must equal the
  displayed headline. A page with several options (colours, scents) is read only when every
  option has the same price; otherwise `parse_failure`. On 2026-10-19, 92 of the 93 momo links
  in the product table read `ok`; 33 of them have several options, each at one price. Blocks get
  one retry with a different user agent; headless Chrome and proxies (8.2) are not implemented.
  A 網頁無法顯示 page gets one more request at the end of the run (8.2); the earlier body is kept
  as `<platform_item_id>__attempt<n>.html.gz`.
  See `momo/README.md` and `momo/VERIFICATION.md`.
- **Coupang** (tested 2026-10-15): the product page at `coupang_url`, requested exactly as stored
  in the product table, from a Coupang page in an everyday Chrome, by the Chrome extension in
  `scrapers/coupang/extension` (`scrapers/coupang/README.md` explains why). Prices are read from
  the HTML as served: JSON-LD (`offers.price`, the `StrikethroughPrice`, `availability`) and the
  price block. Akamai answers every plain request (httr2, curl) with 403 whatever the headers,
  and headless Chrome fails its JavaScript check. From a GitHub-hosted runner every page gets
  403 even in a Chrome window: Akamai refuses those addresses (Q7). An everyday Chrome on a home
  connection got 72 of 72 product pages at the 5-second pace. robots.txt (read in a browser
  2026-10-15) does not disallow `/products/` for `User-Agent: *`; it disallows only some
  `/next-api/` and `/n-api/` paths.

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
  No retry for anything else, except on momo: a 網頁無法顯示 page is requested once more at the
  end of the run (at least 60 seconds later), because momo sometimes serves it for live items
  (6 of 7 such pages loaded normally when re-requested on 2026-10-19).
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

| Period (Taiwan time) | Runs | Backup cron (UTC) |
|---|---|---|
| Oct 19 → Nov 25 | Once a day, 15:07 | `37 7 * * *` |
| **Nov 10, 11, 12** | Two extra runs, 18:07 and 23:07 (flash sales) | `37 10 10-12 11 *` and `37 15 10-12 11 *` |

The runs are seven minutes past the hour because GitHub delays or drops more scheduled runs
on the hour. GitHub's own schedule started the 15:07 run 5.5 and 7.5 hours late on Oct 19 and
20, so since Oct 21 an outside timer starts each run on time (WF-8) and the schedule is only a
backup, 30 minutes after each slot. `scraped_at` records the real time either way.

### 9.2 Workflow requirements

| ID | Requirement |
|---|---|
| **WF-1** | One workflow file, `.github/workflows/scrape.yml`, with the three backup cron entries above and a manual trigger (`workflow_dispatch`). |
| **WF-2** | One job per platform (a matrix over `momo` and `pchome`, with `fail-fast: false`), so one platform failing does not cancel the other. Jobs may run in parallel; the pace rule (NFR-1) is per site. Coupang is not in the workflow: GitHub's runners are refused (Q7), and it was dropped from the daily snapshots on 2026-10-20. |
| **WF-3** | Scheduled and timer runs outside Oct 19 – Nov 25 (Taiwan date) do nothing and end green. Other manual runs always run, for testing and make-ups. |
| **WF-4** | R 4.6.1 via `r-lib/actions/setup-r`, packages via `r-lib/actions/setup-r-dependencies` (cached binaries, not source builds). |
| **WF-5** | `SCRAPER_CONTACT` comes from a repository secret of the same name. |
| **WF-6** | After the scraper step, whatever its exit code, the job uploads that run's output file and `raw/` folder from `scrapers/<platform>/` as one workflow artifact named `<platform>_<run date>_<run time>`, kept 90 days. This is the interim storage until Q6 is answered. |
| **WF-7** | Job timeout 45 minutes. A full run is 150 products × 5 s ≈ 13 minutes, plus retries. |
| **WF-8** | An outside timer (cron-job.org, time zone Asia/Taipei) starts each run at its slot time with a `workflow_dispatch` call carrying the input `timer=true`, using a fine-grained token that can only run this repo's workflows. A scheduled backup does nothing when a manual run of the workflow started since 10 minutes before its slot and has not failed; otherwise it collects the slot itself, late. |
| **WF-9** | Each platform's job reports to its own Healthchecks.io check (ping URLs in the repository secrets `HEALTHCHECKS_MOMO` and `HEALTHCHECKS_PCHOME`), with the FR-8 summary line and the run link. It reports a failure when fewer than 90% of the products end `ok` or the scraper stopped early. Each check expects a report daily by 15:07 Taiwan time with a one-hour grace period, so Healthchecks.io emails when a run fails, reads badly or never happens. Pause both checks after Nov 25. |

### 9.3 Watching the runs

GitHub emails scheduled-run failures to whoever last edited the cron lines, and failures of
timer runs to the owner of the timer's token, so those people watch. A backup that collects
shows the warning "No run for the … slot yet": the timer missed that slot. A failed or missing run is made up with a manual run as soon as it is noticed. Never
back-fill a missed run by copying another run's values.

---

## 10. Non-functional requirements

| ID | Requirement |
|---|---|
| **NFR-1 Pace** | 5 seconds between requests to the same site by default, retries included. Change it if that helps get past a block. |
| **NFR-2 Identity** | User agent `PBA-Double11-study (NTHU ISS4066; contact: <SCRAPER_CONTACT>)`, where `SCRAPER_CONTACT` is an environment variable holding the team's contact email: in `.Renviron` at the project root locally, a repository secret on GitHub (WF-5). This is the default; it may be changed to get past a block (section 8.2). Coupang's pages are requested with the collecting browser's own user agent: Akamai refuses any other. |
| **NFR-3 robots.txt** | The builder checks each site's robots.txt against the URLs the scraper requests, before going live, and records the date checked in 7.3. The scraper does not parse robots.txt at run time. |
| **NFR-4 Getting past blocks** | Blocks are worked around, not accepted (section 8.2). Proxies, headless or real browsers, rotating user agents and any other workaround are all allowed. |
| **NFR-5 Language** | R 4.6.1, with `httr2`, `rvest` and `jsonlite` (the course's language), plus `chromote` (headless Chrome) for pages that block plain requests. CSV writing and gzip use base R. Any other package that helps is allowed; list it here when you add it. Added: `processx` (starts Chrome; Coupang) and `xml2` (installed with rvest; Coupang). Coupang's pages are loaded by a Chrome extension written in JavaScript (Q7); R still reads them. |
| **NFR-6 Secrets** | Tokens, passwords and the contact address go in `.Renviron` or GitHub secrets, never in git. `.Renviron`, `output/` and `raw/` are listed in `.gitignore`. |
| **NFR-7 Reliability** | One product failing never stops the run. |

---

## 11. BigGo price history format: `biggo/price_changes.csv`

Record **change points only**, one row per price change. R turns these into daily prices. How
the rows are collected (by hand, a script, browser automation) is up to the owner; `biggo/README.md`
has what is known about BigGo's history data.

| Column | Type | Content |
|---|---|---|
| `product_id` | text | From the product table |
| `platform` | text | Platform of the BigGo listing: `momo`, `pchome`, `coupang` |
| `biggo_url` | text | The product-table link for that platform (`biggo_url_<platform>`) |
| `changed_at` | `YYYY-MM-DD HH:MM` | Timestamp as BigGo shows it |
| `price` | integer | Price after the change, NT$ |
| `entered_by` | text | The owner's first name |
| `entered_on` | `YYYY-MM-DD` | Date the row was collected |
| `note` | text | Anything odd (gap in history, seller changed). Otherwise `NA` |

- **Period:** Oct 1 to Nov 25, in 2025 and in 2026. 2025 is collected now; 2026 after collection
  ends on Nov 25.
- Include the last change **before** the period starts, so the first day's price is known.
- About 10% of listings are collected a second time, or checked against BigGo's chart, as a
  check; differences are resolved and noted. The owner does this (changed 2026-10-22: the whole
  of BigGo is one person's work).

---

## 12. Deliverables and deadlines

| # | Deliverable | Owner | Due |
|---|---|---|---|
| D1 | Scraper tested on 3 products of the owner's choice | Each scraper owner, for their platform | Wed Oct 14 |
| D2 | Full product table, 150 products (~100 until 2026-10-20) | Alicia, Audrey | Sat Oct 17 |
| D3 | PChome scraper passing section 13 | Albert | Sat Oct 17 |
| D4 | momo scraper passing section 13 | Jordan | Sat Oct 17 |
| D5 | Coupang scraper passing section 13 | Marvin | Sat Oct 17 |
| D6 | Workflow (section 9) passing section 13, manual run green on momo and PChome; Coupang's extension set up on Marvin's laptop (Q7) | Marvin | Sun Oct 18 |
| D7 | First scheduled run on all three platforms | all | **Mon Oct 19** |
| D8 | 2025 BigGo history | Albert | Sun Oct 25 (Milestone 2) |
| D9 | Extra runs on Nov 10 to 12 | all | Thu Nov 12 |
| D10 | Collection stops; workflow disabled; every run's output saved to the Q6 location | all | Wed Nov 25 |
| D11 | 2026 BigGo history | Albert | Sun Nov 29 |

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
- [ ] One platform's job failing leaves the other to finish.

## 14. Open questions

| # | Question | Who answers | Status |
|---|---|---|---|
| Q1 | Does momo show a crossed-out 市價 on product pages? | momo owner | **Answered 2026-10-19:** yes, a struck 市售價 on 70 of 92 pages; see 7.3 |
| Q2 | Does Coupang show a crossed-out 原價? What second prices appear? | Coupang owner | **Answered 2026-10-15:** yes, a struck price (supplier's suggested price, else the 90-day high on Coupang). Second prices: a first-purchase price (首購折扣價) built into the headline for visitors not logged in, and card prices (e.g. 王道卡 特惠價); also bank cashback, shown as text. See 7.3 |
| Q3 | How do momo and Coupang show third-party sellers? | Platform owners | **momo (2026-10-19):** none of the 93 product-table pages showed a third-party seller; markers in 7.3. **Coupang (2026-10-15):** a `賣家：<name>` line with a seller rating, and no Rocket badge |
| Q4 | Does BigGo's history show the 原價 as well as the price? How often does it check prices? | BigGo owner | **Answered (first half) 2026-10-22 (Marvin):** no 原價. BigGo's history view and the history response behind it give a timestamp and a price per point, nothing else; checked on momo and PChome listings. How often BigGo checks prices is still open: spacing varies, from a point a day to a few points in two years. See `biggo/README.md` |
| Q5 | Do the scrapers run on GitHub Actions or on a laptop with Task Scheduler? | Team | **Closed 2026-10-13: GitHub Actions** (section 9) |
| Q6 | Where are snapshots and raw pages kept long term? (The scrapers and workflow live in this repo.) Until decided, outputs live as 90-day workflow artifacts (WF-6), the earliest of which expire around Jan 17; decide before the final report (Dec 20). The repo is public (checked 2026-10-13), so artifact storage has no quota; if it is made private, GitHub Free's 500 MB artifact quota applies and the raw pages may approach it. | Team | Open |
| Q7 | Coupang refuses GitHub-hosted runners: Akamai answers every request from them with 403 (tested 2026-10-15). Where does the Coupang scraper run? A team member's computer in Taiwan as a self-hosted runner (it must be on at every run time), a paid proxy, or no Coupang snapshots (BigGo history only)? | Team | **Answered 2026-10-15 (Marvin):** on Marvin's laptop, in his everyday Chrome, which Coupang serves normally. A Chrome extension saves the pages at each run time (the laptop must be awake: it ignores wake timers, so the wake task tried for this was removed on 2026-10-19); each run reports to Healthchecks.io, which emails when a run fails or is missing; `scrape_coupang.R --saved` writes the CSVs. Outputs are copied to the Q6 storage by hand. See `scrapers/coupang/README.md`. **Superseded 2026-10-20:** Coupang was dropped from the daily snapshots (BigGo history only); the extension is switched off. It collected on Oct 19 and 20 only |
