# Coupang scraper

Owner: **Marvin**. Built to [`../data-collection-spec.md`](../data-collection-spec.md).

## How the runs are collected

Coupang refuses every automated client that was tried, and every request from GitHub's runners
(see [below](#why-an-everyday-chrome)). An everyday Chrome on a Taiwanese home connection is
served normally, so the pages are loaded there, on Marvin's laptop (spec Q7):

1. **A Chrome extension** ([`extension/`](extension/)) in Marvin's everyday Chrome. At each run
   time of the spec (section 9.1) it opens Coupang's home page in a minimised window, requests
   each Coupang product page of `products/products.csv` from that page, 5 seconds apart, and saves
   every response body to `Downloads\coupang-snapshots\<run date>_<run time>\`, with the product
   table it used (`products.csv`) and a record of the run (`run.json`). About 100 products take
   about 10 minutes; the window closes when the run is done.
2. **R** turns the saved runs into the spec's files:

   ```
   Rscript scrapers/coupang/scrape_coupang.R --saved
   ```

   Every saved run that has no CSV yet becomes `output/coupang_<run date>_<run time>.csv` and
   `raw/<run date>_<run time>/`, with the same rules as the rest of the spec (sections 7 and 8),
   and its summary line (FR-8) is printed. Run it whenever you like: a run is never converted
   twice, and a run Chrome is still saving is left for later. It exits 1 when a converted run
   has no `ok` row or could not be converted (FR-9). Saved runs somewhere else:
   `--saved <folder>`, or `COUPANG_SAVED_DIR=<folder>` in `.Renviron`.
3. **Healthchecks.io** gets a report from every run. It emails when a run fails, and when no
   report has arrived an hour after the run time, which also covers a laptop that was off.

The extension reads the product table from GitHub (`main` branch), so changes to
`products/products.csv` reach it once they are merged. If GitHub cannot be reached, it uses the
last table it downloaded and says so in `run.json`. The rows' `source` is `scraper`, as for the
other platforms.

### Setting it up (once)

On the laptop that collects (Windows, time zone Taipei, Chrome):

1. **Extension.** Open `chrome://extensions`, turn on *Developer mode*, click *Load unpacked* and
   pick the `scrapers/coupang/extension` folder. Pin it to the toolbar, open it and click
   *Test run* (see [Day to day](#day-to-day)). It keeps Chrome running in the background after
   its last window is closed, and starts Chrome with Windows, so runs happen without opening
   Chrome. Chrome loads it from that folder, so keep the project on a branch that has it.
2. **Healthchecks.io.** Create a free account and a check with schedule *Cron* `7 15 * * *`,
   time zone `Asia/Taipei`, grace time 1 hour, and paste its ping URL into the extension's
   *Settings*. For the extra runs on Nov 10–12, a second check with cron `7 18,23 10-12 11 *`
   goes into the second field; without it, those runs report to the first check.
3. **Power.** At run times the laptop must be plugged in, **awake** and signed in to Windows (a
   locked screen is fine). Nothing wakes it: a scheduled task with a wake timer was tried and
   removed, because Marvin's laptop (Lenovo IdeaPad, Modern Standby) ignored the timer from sleep
   and from hibernate (tested 2026-10-16 and 2026-10-19). So don't put it to sleep before a run;
   to close the lid, first set *closing the lid* to *Do nothing* when plugged in (Control Panel →
   Power Options). Once a run has started, the extension keeps the laptop awake until it ends.

### Day to day

- Nothing needs doing at run times.
- **When something goes wrong**, Healthchecks emails and the extension's icon shows a red `!`.
  The popup lists recent runs and what each got. Make up a failed or missed run with *Run now*
  as soon as it is noticed (spec 9.3). A run missed because Chrome or the laptop was off runs by
  itself once they are back on, if that is still the same day.
- **Converting**: run the `--saved` command above, then copy `output/` and `raw/` to the team's
  storage (Q6).

*Test run* in the popup checks that collecting works, at any time, without touching the study's
runs: it requests the pages of [`extension/test_products.csv`](extension/test_products.csv),
saves them to `Downloads\coupang-snapshots-test\` (which `--saved` does not read), and is not
reported to Healthchecks or shown on the icon. Its result is listed under *Recent runs* after
about a minute.

## Why an everyday Chrome

Coupang is behind Akamai Bot Manager. What was tried on 2026-10-15:

| Client | Result |
|---|---|
| httr2 or curl, any user agent and headers | `403 Access Denied`, every time. Akamai recognises non-browser connections, not just their headers |
| Headless Chrome (chromote's default), even with a normal Chrome user agent | Akamai's JavaScript check runs, fails, and the page reloads into a 403 |
| `scrape_coupang.R`'s own Chrome window (driven through chromote) on a GitHub-hosted runner | `403 Access Denied` on every page, before any page or check is served: Akamai refuses GitHub's data-centre addresses outright. Backing off and a fresh profile change nothing |
| The same window on Marvin's home connection | After the headless tests failed, every fresh session from that address got 403 at once: the address looked flagged |
| Marvin's everyday Chrome, same address, at the same time | Served normally: 72 of 72 product pages, requested from a Coupang page 5 seconds apart, came back complete (HTTP 200) |

Each failed attempt also makes Akamai more suspicious of the address for a while, so plain
requests are never tried first: they only cost requests and make the next ones less likely to
get through.

The extension requests each page the way the Coupang page itself would, with the browser's own
cookies and user agent (the spec's study user agent, NFR-2, would be refused outright). Not done,
on purpose: disguising automation to fool Akamai's checks, or solving its challenges. If Coupang
refuses the everyday browser too, the products are recorded as `blocked`.

### Getting past Akamai (section 8.2)

When a page comes back blocked (403, Akamai's "Access Denied", Coupang's "你沒有權限存取此頁面"
page, or Akamai's JavaScript check), the extension waits 60 seconds and tries again, then goes
back through Coupang's home page and tries once more. Only then is the product `blocked`. After
three blocked products in a row it stops doing this and gives each remaining product a single
try, so a run in which Akamai refuses everything stays short and does not keep hitting the site.
A timeout, a connection error, a 429 or a 5xx gets one retry after 60 seconds.

### The script's own browser (not used for the runs)

`Rscript scrapers/coupang/scrape_coupang.R [product_table.csv]` loads the pages itself, in a
normal Chrome window with its own profile in `scrapers/coupang/.chrome-profile/` (git-ignored),
with the same rules (except that it starts a fresh profile where the extension goes back through
the home page). It needs `SCRAPER_CONTACT` in `.Renviron`, the R packages `chromote`, `rvest` and
`jsonlite`, and a screen (`xvfb-run` on a server). `SCRAPER_PROXY` (e.g. `http://host:port`)
sends its traffic through a proxy. It is kept for a connection Akamai has not flagged; it has not
yet got a page through.

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
  (1 + 198 = 199); otherwise the row is `parse_failure` and the page is kept for a fix. The
  collecting Chrome is not logged in to Coupang, so it sees what any visitor sees.
- **Time-limited discounts** look the same with the label `折扣後價格`, e.g. `$590` crossed out,
  `$425`, and under it `$65 折扣後價格 · 折扣剩下8小時`. Like momo's 限時折後價, the headline goes
  to `extra_price` (label `折扣後價格`) and `sale_price` is the price without the discount. When
  that price is not the crossed-out one, the line under the headline shows it, crossed out
  (`… $490`), and the scraper takes it from there (425 + 65 = 490). First-purchase lines do
  this too (`$200 首購折扣價 $1,260`). Seen on 5 of 37 pages on 2026-10-19.
- **Card prices.** Prices for one bank card (e.g. `王道卡 特惠價 $3,410` under 刷卡優惠) also
  count for `extra_price`, which takes the lowest conditional price shown.
- **Discount badges** on product pages are `N折`, never a percentage, so `shown_discount_pct` is
  `NA` and the badge goes to `promo_tag` (spec 7.2).
- **Wrong or dead links.** Coupang answers a wrong link and an item it no longer sells with the
  same page, with HTTP 200: 找不到商品。網址輸入錯誤，或該商品已結束銷售或暫停銷售。 The two
  cannot be told apart, so the row is `parse_failure` and the log says which page it was.
  An item that is sold out but still listed comes out as `ok` with `in_stock` `FALSE`.
- Text from separate parts of the page (a card name and its price, a bank and its reward) is
  joined with one space.

## Raw pages

`raw/<date>_<time>/<itemId>.html.gz` is the page the row was read from. When one product got
more than one response (a failed try before a retry, a block page), the earlier ones are kept
too, as `<itemId>_1.html.gz`, `<itemId>_2.html.gz`, … in the order they arrived. (The extension
names them `<itemId>_try1.html.gz`, `<itemId>_try2.html.gz`, …; `--saved` renames them.)

## Tests

From the project root:

```
Rscript scrapers/coupang/tests/test_saved_runs.R
Rscript scrapers/coupang/tests/test_parse_product_page.R
```

`test_saved_runs.R` builds saved runs as the extension writes them and checks the CSV rows and
`raw/` files `--saved` makes from them; `test_parse_product_page.R` checks the parser on markup
copied from real pages (`tests/fixtures/`). Run them by relative path: Rscript crashes when given
an absolute path containing an apostrophe.

`extension/test_products.csv` holds three real products (a plain discount with a card price, a
first-purchase price, a third-party seller), a link to a product that does not exist, and a
link without `itemId`.

Checked on 2026-10-15:

- A table with a link without `itemId`, a duplicated `product_id` and a non-Coupang link gives
  `bad_input` rows with the reason in the log, and the run carries on.
- Without `SCRAPER_CONTACT`, with a column missing or with no table, the script's own browser
  mode exits 1 and writes no file. A second run in the same minute stops and leaves the first
  file alone; so does converting a saved run a second time.
- Times are Taiwan time even when the computer's clock is set to UTC.
- On a GitHub-hosted runner (Linux, under `xvfb-run`) the script's own browser works as designed
  (blocked rows, back-off, fresh profile, raw pages saved, exit code 1), but every page is
  refused.

A sold-out page was first seen in the 2026-10-19 15:07 run: two items showed 暫時缺貨 with JSON-LD
`OutOfStock` and came out `ok` with `in_stock` `FALSE`. Not checked yet: 11.11 campaign labels.
