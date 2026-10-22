# BigGo price history

Owner: **Albert** · 2025 history due **Sun Oct 25** (Milestone 2) · 2026 history due **Sun Nov 29**

## The task

Fill **`biggo/price_changes.csv`** (this folder) with the price history of every product on every
platform it has a BigGo link for, in the format of section 11 of
[`scrapers/data-collection-spec.md`](../scrapers/data-collection-spec.md). The file is already here
with its header line. How the rows are collected is up to Albert: by hand, a script, or browser
automation.

- One row per **price change**. Oct 1 to Nov 25, in 2025 and in 2026, plus the last change before
  Oct 1 so the first day's price is known.
- `entered_by` is `Albert`; `entered_on` is the day the row was collected.
- Collect about 10% of listings a second time, or check them against BigGo's chart, and note any
  differences in `note`.
- Scripts that fill the file go in this folder.

## What BigGo's history contains (checked 2026-10-22, Marvin)

Looked at on one momo and one PChome product.

- **No 原價.** BigGo's history gives a timestamp and a price per point, nothing else (answers the
  first half of spec Q4). The crossed-out price only comes from our own daily snapshots.
- **The window is at most 2 years back from today** (the page offers 90 days, 180 days, 1 year,
  2 years; the series starts on the day 2 years ago). Oct to Nov 2025 stays inside it until
  about Oct 2027.
- **Points about a day apart, even when the price did not change.** The spec wants change points
  only, so drop a point whose price equals the one before it.
- Timestamps in the response are UTC, in milliseconds. The spec's `changed_at` is Taiwan time
  (UTC+8).
- The same product can flip between two prices several times a day (3C-003 on momo went
  490 / 590 / 490 / 590 on consecutive days in Aug 2026). Keep every change as BigGo shows it;
  the analysis decides what to do with it.

## `biggo_url_*` in the product table is a search page, not a listing

`products/products.csv` links to a BigGo **search** (`biggo.com.tw/s/<query>/?m=cp&c[]=<shop>`).
That page can show several listings: for 3C-003 on momo it showed three, and the first result was
a different item (id `14562513`) from the product in `momo_url` (`i_code=8697108`). Reading the
history off the first result would give the wrong product.

BigGo's history is looked up by an id that is the shop code plus the platform's own item id, the
id the scrapers already extract from `momo_url` and `pchome_url`:

| Platform | Shop code | Item id | Example `history_id` |
|---|---|---|---|
| momo | `tw_pec_momoshop` | `i_code` | `tw_pec_momoshop-8697108` |
| PChome | `tw_ec_pchome24h` | the id after `/prod/` | `tw_ec_pchome24h-DYAJD2-A900GAFRM` |
| Coupang | `tw_pec_coupang` (from the product-table links) | not tested | |

The history view on the page calls `POST https://biggo.com.tw/api/v1/spa/product/history` with
`{"history_id": "<id>", "days": 730}`, and the reply holds `current_price`, `title`, `purl` and
`price_history`, a list of `{x: timestamp, y: price}` points. Both examples above returned a
series; only the title of the momo one was compared with the product.

This is the page's own request, not a documented API. It can change without notice.

## Conduct

- `robots.txt` checked 2026-10-22: it allows everything except paths under `/r/`.
- BigGo's terms of use were not read (team decision, 2026-10-22).
- Follow the scrapers' pace and identity rules (spec NFR-1 and NFR-2): 5 seconds between requests,
  and the team's contact in the user agent. 335 listings at that pace is about 30 minutes.
- No login, no personal data (spec section 3).
