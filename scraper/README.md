# momo price recorder

The initial momo-only input contains **7 confirmed single-option listings**. The remaining
**93 original products** are tracked in [the review queue](../data/momo-review-queue.json).
The original Productss.csv is unchanged. This operational subset does not certify the
broader study's cross-platform or BigGo eligibility.

## Run

From the repository root, with R installed:

```powershell
Rscript scraper/install_dependencies.R
Rscript scraper/scrape_momo.R
```

Dependencies are httr2, rvest and jsonlite. The installer only installs missing packages into
the ignored project-local .R-library. It does not update installed packages.

Copy .Renviron.example to .Renviron and set PBA_CONTACT_EMAIL before the first request.
The contact supplied in this chat is already configured locally; .Renviron is git-ignored.
No login, cookies, tokens or browser session are needed.

On this computer R is installed but Rscript is not on PATH. The equivalent command is:

```powershell
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' scraper/scrape_momo.R
```

For a smaller run:

```powershell
Rscript scraper/scrape_momo.R --limit 3
Rscript scraper/scrape_momo.R --ids 3C-020,FOOD-016
```

Optional path flags are --products, --output-dir, --raw-dir and --log-dir. Defaults resolve
against this repository rather than the shell's current directory. Relative override paths
resolve against your current directory. Options take one value each.

Each invocation performs **one run**. No recurring job has been installed. Repeated manual or
scheduled invocations append fresh snapshots; earlier actual selling prices become your
observed history. Do not backfill a missed day from today's price. Daily scheduling is a
separate setup step.

## Current confirmed input

| Product ID | Product | momo code | Locked option |
|---|---|---|---|
| 3C-020 | SanDisk Ultra Flair USB3.0 128GB company stock, one drive | 5904337 | 001 / 單一規格 |
| FOOD-011 | Pocari original 580ml ×24 | 3974750 | 001 / 單一規格 |
| HOME-009 | 3M pot/stove Scotch-Brite scourers, four pieces | 8937853 | 001 / 單一規格 |
| FOOD-009 | Original Coke 330ml ×24 | 10076881 | 001 / 單一規格 |
| FOOD-010 | Coke Zero 330ml ×24 | 6624888 | 001 / 單一規格 |
| FOOD-016 | Ferrero Rocher T16, 16 pieces / 200g, one box | 11889463 | 001 / 單一規格 |
| FOOD-012 | Evian 500ml ×24, company stock | 12121299 | 001 / 單一規格 |

[data/products.csv](../data/products.csv) owns all active product IDs, URLs and expected titles.
It retains the spec's input columns and adds momo_url, momo_variant_sku, momo_variant_label
and momo_expected_title. Cross-platform IDs are intentionally blank until independently
approved for their recorders. Optional historical references are listing-specific leads,
not full transcriptions.

The recorder requires one JSON-LD ProductGroup with the requested code, one matching variant,
the exact reviewed schema title, a matching visible 品號, TWD currency, and agreement between
the schema offer and the visible headline. Different sizes sold through separate product
links are not selectable variants of this listing. Multiple actual hasVariant entries are
held for review; no default option is guessed. A harmless title edit can also trigger a
review rather than silently weakening the match.

To add a pending product: inspect its public page, confirm exact size/colour/formula/pack
count and seller, record its title and sole variant SKU/label, then add one row to products.csv.
Preserve the original product ID for the same physical product. A different replacement needs
a new ID. Update the review queue and evidence log when promoting a row. Multi-option pages
need additional implementation/verification before promotion.

## What a snapshot means

The recorder writes the spec's exact 16 columns, in order, as UTF-8 CSV with NA for missing
values. It does not calculate discounts, use prices from another day or click coupon/login
dialogs.

- original_price: the amount explicitly labelled 市售價 / 市價 / 原價.
- sale_price: the amount explicitly labelled 促銷價 / 售價, before a further condition.
- extra_price and extra_price_label: the lowest explicit conditional amount in the main price
  block, with its label copied. If none is shown there, NA.
- promo_tag and coupon_note: visible campaign and coupon/card wording in the product purchase
  column. Percent-off is only copied from explicit percent-off wording; 85折 is not converted
  into a percentage. Multi-buy savings and cashback are not converted into a single-item price.
- seller_type: the provisional normal-catalogue default in spec §6.3. Suspected third-party
  markers fail validation. This is not an independent legal seller audit.
- in_stock: the spec's no-sold-out-notice rule, supplemented by explicit schema unavailability
  if present. It is not a successful checkout test.

For example, Ferrero displayed 市售價 299, 促銷價 275 and 限時折後價 233 on October 18:
the columns contain 299, 275, 233 respectively. The schema price was 233, so blindly using it
as sale_price would have mixed a conditional price into the ordinary price series.
A crossed-out amount is momo's displayed comparison price; it is not proof of a previous sale.

Selectors are based on the current public HTML data-testid price blocks. A missing or
unrecognized layout/label fails conservatively with NA prices and a diagnostic log entry.
Legacy layouts are not guessed. Member-only and hidden coupon amounts are not fetched.

## Files and failures

- data/snapshots/momo_YYYY-MM-DD.csv: real snapshots in Taiwan time. A rerun appends rows and
  writes no extra header. Request date controls the destination even across midnight.
- data/logs/momo_YYYY-MM-DD.jsonl: run IDs, request outcomes, raw paths and failure reasons.
  Only content-type/date/cache-control/location response headers are retained; cookies are
  excluded. Logs are diagnostics, not price observations.
- raw/momo/YYYY-MM-DD/ITEM.html.gz: first capture for the item that day.
- raw/momo/YYYY-MM-DD/run-HHMMSS-PID-NONCE/ITEM.html.gz: every run's separate capture, so
  reruns do not overwrite raw evidence. robots.txt responses are archived here too.
- data/momo-listing-evidence.json: the initial page/option observations and inspection prices.

HTTP failures, changed products/options and parse failures still generate rows with NA
prices. A 200 error page retains status 200; an unexpected redirect retains its actual 3xx
status. The recorder deliberately does not follow redirects. Errors return a nonzero exit
after rows are saved.

Each run checks robots.txt, uses the study contact user agent and waits at least five seconds
between request starts (or a longer robots crawl-delay). Only public /product/ pages are
requested. No /api/ or /ajax/ calls, browser impersonation, proxies or access-control workarounds
are used.

A 403, 429 or detected challenge stops further product requests. The blocked product keeps
its actual HTTP status; remaining unrequested products get NA status/prices with a specific
log reason. If robots.txt is unavailable, product requests do not start. An output-directory
lock prevents simultaneous writes; after a forcibly terminated process, verify it is no
longer running before removing a stale data/snapshots/.momo-lock directory.

Raw pages are git-ignored. The spec also requires shared-Drive backup; automatic upload has
not been configured by this implementation.

## Verification

```powershell
Rscript tests/test_momo.R
```

The offline checks exercise price separation, variant/title changes, currency, schema/HTML
disagreement, UTF-8, missing prices, 404 continuation, 403 stopping, robots policy, appending
and raw preservation. They use temporary test outputs, never the real snapshot directory.
See [momo-verification.md](../momo-verification.md) for live-run results.

