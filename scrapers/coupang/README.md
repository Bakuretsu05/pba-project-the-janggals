# Coupang scraper

Owner: **Marvin**. Built to [`../data-collection-spec.md`](../data-collection-spec.md).

## Running it

From the project root:

```
Rscript scrapers/coupang/scrape_coupang.R                  # products/products.csv
Rscript scrapers/coupang/scrape_coupang.R my_test_table.csv  # any other product table
```

It needs:

- `SCRAPER_CONTACT` in `.Renviron` at the project root (`SCRAPER_CONTACT=someone@example.com`).
  Without it the run does not start.
- Google Chrome, and the R packages `chromote`, `rvest` and `jsonlite`
  (`install.packages(c("chromote", "rvest", "jsonlite"))`).
- A screen. A Chrome window opens and stays open during the run; leave it alone. On a server
  with no screen, run the command under `xvfb-run`.
- A home internet connection in Taiwan. Coupang refuses GitHub's own runners (see below).

The run writes `output/coupang_<date>_<time>.csv` (one row per product), keeps every page it
received in `raw/<date>_<time>/`, and ends with the summary line from FR-8. A full run of about
100 products takes about 15 minutes.

## Why a Chrome window and not httr2

Coupang is behind Akamai Bot Manager. What was tried on 2026-10-15:

| Client | Result |
|---|---|
| httr2 or curl, any user agent and headers | `403 Access Denied`, every time. Akamai recognises non-browser connections, not just their headers |
| Headless Chrome (chromote's default), even with a normal Chrome user agent | Akamai's JavaScript check runs, fails, and the page reloads into a 403 |
| This scraper (a normal Chrome window) on a GitHub-hosted runner | `403 Access Denied` on every page, before any page or check is served: Akamai refuses GitHub's data-centre addresses outright. Backing off and a fresh profile change nothing |
| This scraper on Marvin's home connection | Not confirmed yet. After the headless tests failed, every fresh session from that address got 403 at once, while an ordinary browser that already had Coupang cookies kept working: the address looks flagged for a while |

Each failed attempt also makes Akamai more suspicious of the IP address for a while, so the
scraper does not try plain requests first: they only cost requests and make the next ones
less likely to get through.

**Where it can run.** Not on GitHub-hosted runners. It needs a Taiwanese home connection whose
address Akamai has not flagged, e.g. a team member's computer registered as a self-hosted
GitHub Actions runner, or a proxy (`SCRAPER_PROXY`). This is open question Q7 in the spec. Run
it once by hand from that connection before relying on it.

The script therefore starts a normal Chrome window with its own profile in
`scrapers/coupang/.chrome-profile/` (git-ignored) and loads each product page there, like a
person browsing. The profile keeps Coupang's cookies from one run to the next. The user agent is
Chrome's own; the spec's study user agent (NFR-2) would be refused outright. `SCRAPER_CONTACT` is
still required, as the spec says.

### Getting past Akamai (section 8.2)

When a page comes back blocked (403, Akamai's "Access Denied", Coupang's "你沒有權限存取此頁面"
page, or a JavaScript check that never finishes), the scraper waits 60 seconds and tries again,
then restarts Chrome with an empty profile and tries once more. Only then is the product
`blocked`. After three blocked products in a row it stops doing this and gives each remaining
product a single try, so a run in which Akamai refuses everything stays short and does not
keep hitting the site. Setting `SCRAPER_PROXY` (e.g. `http://host:port`) sends Chrome's traffic
through that proxy.

Not done, on purpose: disguising the automated browser to fool Akamai's checks, or solving its
challenges. If a normal Chrome window is refused, that is recorded as `blocked`.

## How the page is read

Everything is read from the HTML the server sent, which is also what is saved in `raw/`, so a
saved page can be parsed again after a fix. Section 7.3 of the spec lists where each column
comes from. Points worth knowing for the analysis:

- **The crossed-out price.** Coupang's own explanation (in the page data): it is the supplier's
  suggested retail price or the official sales channel's price; if there is none, the highest
  price the item sold for on Coupang in the last 90 days.
- **First-purchase prices.** For many items a visitor who is not logged in sees a headline price
  that already includes a first-purchase coupon, e.g. `0.1折 $1`, `$199` crossed out, and under it
  `$198 首購折扣價 · 折扣剩下9小時`. That headline is a conditional price, so it goes to
  `extra_price` with the label `首購折扣價`, and `sale_price` is the price without it ($199,
  shown crossed out). The scraper only does this when the page's own figures add up
  (1 + 198 = 199); otherwise the row is `parse_failure` and the page is kept for a fix.
- **Card prices.** Prices for one bank card (e.g. `王道卡 特惠價 $3,410` under 刷卡優惠) also
  count for `extra_price`, which takes the lowest conditional price shown.
- **Discount badges** on product pages are `N折`, never a percentage, so `shown_discount_pct` is
  `NA` and the badge goes to `promo_tag` (spec 7.2).
- **Wrong or dead links.** Coupang answers a wrong link and an item it no longer sells with the
  same page, with HTTP 200: 找不到商品。網址輸入錯誤，或該商品已結束銷售或暫停銷售。 The two
  cannot be told apart, so the row is `parse_failure` and the run log says which page it was.
  An item that is sold out but still listed comes out as `ok` with `in_stock` `FALSE`.
- Text from separate parts of the page (a card name and its price, a bank and its reward) is
  joined with one space.

## Raw pages

`raw/<date>_<time>/<itemId>.html.gz` is the page the row was read from. When one product got
more than one response (Akamai's check page, a failed try before a retry), the earlier ones are
kept too, as `<itemId>_1.html.gz`, `<itemId>_2.html.gz`, … in the order they arrived.

## Tests

`test_products.csv` holds three real products (a plain discount with a card price, a
first-purchase price, a third-party seller), a link to a product that does not exist, and a
link without `itemId`:

```
Rscript scrapers/coupang/scrape_coupang.R scrapers/coupang/test_products.csv
```

Checked on 2026-10-15:

- A table with a link without `itemId`, a duplicated `product_id` and a non-Coupang link gives
  `bad_input` rows with the reason in the log, and the run carries on.
- Without `SCRAPER_CONTACT`, with a column missing or with no table, the run exits 1 and writes
  no file. A second run in the same minute stops and leaves the first file alone.
- Times are Taiwan time even when the computer's clock is set to UTC.
- The parser gives the right columns for page markup copied from the three test products.
- On a GitHub-hosted runner (Linux, under `xvfb-run`) the whole run works as designed (blocked
  rows, back-off, fresh profile, raw pages saved, exit code 1), but every page is refused.

Not checked yet, because no automated page load has got through: the CSV for the three products
against what a browser shows, and a sold-out page.
