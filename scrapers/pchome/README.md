# PChome scraper

Owner: **Albert**. Build it to [`../data-collection-spec.md`](../data-collection-spec.md).

## Run

Use R 4.6.1. Install the course packages once:

```r
install.packages(c("httr2", "rvest", "chromote"))
```

Set `SCRAPER_CONTACT=your-contact-email` in the ignored `.Renviron` at the repository root.
From that root:

```sh
Rscript scrapers/pchome/scrape_pchome.R
Rscript scrapers/pchome/scrape_pchome.R scrapers/pchome/tests/products_test.csv
Rscript scrapers/pchome/scrape_pchome.R scrapers/pchome/tests/products_errors.csv
Rscript scrapers/pchome/tests/test_scraper.R
```

The first command uses `products/products.csv`. The separate test tables do not change the
team's selections and do not certify cross-platform or BigGo-history eligibility. The three
real test listings are AirPods 4, a black Logitech M331, and the conditional-price soy milk
listing that exposed the API discrepancy. Test identifiers are local to these tables.

Ensure `Rscript` from your R installation is on PATH and the required packages are installed.

## Collection behavior

- The CSV has the specification's exact 17 columns, UTF-8 text, and literal `NA` values.
- Each run freezes its Taiwan date and minute. Files go to `output/pchome_YYYY-MM-DD_HHMM.csv`
  and `raw/YYYY-MM-DD_HHMM/`. Both are ignored by git.
- A repeated minute fails before any request. A run interrupted before it saved anything
  removes its empty raw folder, so that minute can be run again; saved evidence is kept.
- Every received body is saved unchanged in an `.html.gz`, including error bodies. The body
  the row was read from is `<ID>.html.gz`; earlier attempts are `<ID>__attempt<n>.html.gz`.
  Repeated platform IDs on different product rows add `__rowN`. Nothing is overwritten.
- Requests use the identified study user-agent, a 30-second timeout, at least five seconds
  after the preceding request finishes, and one retry after at least 60 seconds for a connection
  error, timeout, HTTP 429 or 5xx. A longer `Retry-After` is honored, up to 300 seconds.
- Invalid input rows get `bad_input`; every duplicated `product_id` is rejected. Blank PChome
  links are skipped. Other failures retain a row and processing continues.
- Blocks follow spec section 8.2. After a 403, challenge page or repeated 429, the scraper
  waits 60 seconds and requests the page again with a browser user agent, then waits again and
  loads it in a fresh headless Chrome (when `chromote` is installed). Only then is the product
  `blocked`, and the run moves on. After three products in a row end blocked, later products
  get one request each (no 429 retry), so a site refusing everything cannot push the run past
  the 45-minute job limit. On 2026-10-18 headless Chrome got 429 where plain httr2 got 200.
- A challenge is recognised only on a page without the product block, so CAPTCHA scripts or a
  `noscript` notice on a normal product page never block a row.
- Exit is zero if at least one row is `ok`, otherwise one. An empty main product table writes
  a header-only CSV and exits one; this is not a successful full-dataset collection.

## Customer-visible source (team decision, 2026-10-16)

The source is the product page at `https://24h.pchome.com.tw/prod/<ID>`, requested directly
with httr2 and the study identity. The website served server-rendered product HTML with HTTP
200 during testing. The API is no longer requested and no API prices or JSON-LD values are
used as substitutes for customer-visible markup.

The parser checks the page's product identity and limits extraction to its main product
information and price block. Scripts, hidden elements, recommendations and reviews are
excluded. Unknown price layouts, mismatched IDs and unverifiable selected variants give
`parse_failure`; they do not trigger an API fallback. Tracking parameters are removed when
the canonical page URL is built. A suffixed variant URL is accepted only if the page explicitly
identifies that exact variant, rather than silently selecting the base product.

| Field | Visible evidence used |
|---|---|
| `sale_price` | Main selling-price text, before conditional reductions. In the verified 折扣價 / 網路價 layout, the displayed 網路價 is the baseline. A conditional headline without a verified baseline fails parsing. |
| `original_price` | A crossed-out price inside the product price block: semantic `del`/`s`, explicit line-through styling, or the site's `.c-prodPrice__originalPrice` presentation class, visually confirmed on three product pages in the browser. No API `Price.M` is read. |
| `extra_price`, `extra_price_label` | Lowest price in the recognised conditional price blocks whose amount is explicitly linked to a displayed promotion/condition. The corresponding condition is copied from that promotion. Unlinked amounts/labels remain NA. |
| `shown_discount_pct` | Only a standalone percentage badge in the product discount/price badge area. No computed percentage, cashback conversion, or conversion of 折. |
| `promo_tag` | Product header campaign text, discount links, price tags, promotion tags and wording, in DOM order with exact duplicates removed. |
| `coupon_note` | Displayed discount conditions, coupon text and card-benefit links inside the product information area. |
| `seller_type` | `platform`: 24h product pages are sold by PChome itself (spec 7.3). |
| `in_stock` | Enabled purchase buttons → TRUE; an explicit sold-out/removed notice in the main product area → FALSE; otherwise TRUE when a selling price is shown (spec 7.1: an `ok` row is never NA). No API quantity default. |

The visible soy milk page has baseline 網路價 285, crossed-out 285, conditional 275, and
`限時活動 10/14 - 10/31 任選1件$275`. The collector records sale 285, original 285, extra 275,
and that condition label. The internal API reference 336 never enters the snapshot.
For M331, both displayed prices are 699 and the second is visibly crossed out: original 699
is preserved. This deliberately replaces the old feed rule that discarded equal prices.
The crossed-out value can therefore equal the pre-condition selling price; analysis must
interpret it together with `extra_price` and its condition rather than inventing a % badge.

## Coverage and access limits

Every run also saves `raw/<stamp>/verification.csv`, separate from the fixed-schema snapshot.
It records source, `visible_text_only` coverage, fields with incomplete coverage, and a note
for every attempted product. The command prints an explicit coverage warning. `ok` means the
selling price or sold-out state was verified, as specified in section 8; it does not certify
that every possible coupon, member offer or promotion has been collected.

Only server-rendered customer-facing text is collected automatically. Client-loaded coupon
details, payment dialogs, personalised/member offers and image-only labels are not fully
verified. Available wording is copied; unavailable amounts and labels remain NA. A recorded
extra price is the lowest among verified displayed candidates, not a guarantee about unseen
offers. These limits affect `extra_price`, `extra_price_label`, `shown_discount_pct`,
`promo_tag` and `coupon_note`. NA does not prove that the website offers nothing further.

On 2026-10-16, product-site robots.txt allowed ordinary `/prod/` pages. The asset host's
robots.txt disallowed all paths, so no direct CSS scraping request was made. The original
price class's strike-through presentation was checked visually in the ordinary browser.
Site HTML/CSS redesigns require revalidation. No robots-disallowed endpoint is used. Recheck site rules before
collection if policy or requested URLs change.

Old feed-based CSVs and JSON responses remain intact as development evidence; they are not
verified visible-page snapshots. Select runs whose verification audit names
`customer_visible_html` for the research dataset. Do not mix historical test outputs blindly.

The automated tests use synthetic page fragments and an injected clock for retry cases,
plus a real refused local HTTP connection. Live tests use actual product HTML. The collector
is ready for daily snapshots of the supported visible-text fields, subject to access and
coverage limits. Complete interactive-offer coverage is not certified. The main product
table still needs to be supplied and validated. GitHub Actions remains Marvin's task.
