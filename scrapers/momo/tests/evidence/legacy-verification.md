# momo recorder verification — 18 October 2026

> Historical prototype report: paths and the 16-column/appending contract below describe the earlier version. The observed snapshot is preserved as `momo_2026-10-18_legacy.csv` in this folder. For the integrated URL-only, 17-column recorder, see [../../VERIFICATION.md](../../VERIFICATION.md).

## Result

The live recorder successfully captured prices for **all seven confirmed momo products**.
The offline suite passed **26 checks**. The original Productss.csv was not edited.

The full seven-product run used Taiwan request times **23:23:13–23:23:44**, with at least
five seconds between request starts. Every product returned HTTP 200 and a parsed price.
The response body for every attempted product was saved as gzip.

| Product | Item code | Displayed original price | Regular selling price | Conditional price | Condition label |
|---|---|---:|---:|---:|---|
| SanDisk Ultra Flair 128GB | 5904337 | 899 | 669 | NA | NA |
| Pocari original 580ml ×24 | 3974750 | 696 | 509 | NA | NA |
| 3M pot/stove scourers, four pieces | 8937853 | 162 | 100 | NA | NA |
| Original Coke 330ml ×24 | 10076881 | 600 | 340 | NA | NA |
| Coke Zero 330ml ×24 | 6624888 | 600 | 340 | NA | NA |
| Ferrero T16 / 200g | 11889463 | 299 | 275 | 233 | 限時折後價 |
| Evian 500ml ×24 | 12121299 | 1320 | 1200 | 1100 | 限時折後價 |

These are observed NT$ amounts at the recorded times, not current-price guarantees or
calculated discounts. The real records are in
[data/snapshots/momo_2026-10-18.csv](data/snapshots/momo_2026-10-18.csv).

## Browser and input checks

SanDisk, Pocari and Ferrero were checked against the live browser's product and price display
(accessibility text). Their item IDs, pack specifications and displayed original/regular/
conditional amounts matched the recorder. Ferrero verifies the important conditional-price
case; SanDisk and Pocari verify ordinary headline prices with no separately displayed
conditional amount.

For all seven inputs, the retrieved JSON-LD identifies exactly one hasVariant entry,
SKU 001 / 單一規格. The product title, source code, sole option and headline/schema amount
are validated again on every run. Multiple actual options or a changed identity cause NA
prices and a review error. This is momo-only recording readiness, not complete cross-platform
or historical-study approval.

## Failure and append checks

A separate **live invalid-ID test** used a deliberately nonexistent numeric momo code,
followed by a valid SanDisk row. momo returned an HTTP **200 error page** for the bad code.
The recorder retained status 200 with NA prices, logged the missing ProductGroup, and
continued to record SanDisk at 669. The command exited with status 1 to report the failed row.
These test-only rows and raw pages are under raw/live-invalid-test/, outside real snapshots.

A mocked HTTP 404 was also tested before a valid row; it preserved 404 and continued.
A mocked 403 stopped subsequent product requests, retained the first row's 403, and wrote
unrequested rows with NA status/prices and an explanatory diagnostic. No live 403 was induced
or bypassed. Invalid robots responses likewise stop product requests.

Same-day appending was verified offline and in the live snapshot file. The file contains
**11 actual observations**: one valid row from an initial interrupted development run, three
from the successful three-product validation, and seven from the full run. Each timestamp is
an actual request; there is exactly one header. The initial interruption was an audit-header
serialization issue after the valid price row had been written; it was fixed before the
successful runs. The valid observation and its raw capture were retained.

Raw capture checks verified byte-for-byte gzip recovery and preservation of both run-specific
copies on a rerun. The top-level daily item file keeps the first capture. Logs retain only
selected non-cookie response headers; initial development logs were sanitized accordingly.

## Offline checks

Run: Rscript tests/test_momo.R

All 26 checks passed, covering separate price roles, Chinese labels/UTF-8, no calculated
percentage from 85折, missing prices, multiple options, changed pack/title, foreign currency,
schema/HTML disagreement, ambiguous price ranges, sold-out notices, challenges, robots rules,
crawl delay, malformed robots responses, failure rows, request stopping, CSV append/header
behaviour, raw preservation, and disjoint seven-confirmed/93-pending inputs.

R is installed locally at C:/Program Files/R/R-4.6.1/bin/Rscript.exe. The httr2 dependency was
installed into the ignored project .R-library; rvest and jsonlite were already available.
The scripts initialize UTF-8 character handling on Windows.

## Remaining scope

93 products remain in the momo-only review queue. Multi-option pages are intentionally not
enabled until their chosen option and price can be verified. Seller and stock use the
project spec's provisional catalogue/no-sold-out-notice rules; they are not checkout or legal
seller certification. The momo seller “check” in the spec remains open.

No recurring schedule or shared-Drive raw backup was configured. Each invocation records one
fresh run. The implementation supports the initial confirmed list now; full 100-product
coverage and broader study eligibility remain separate follow-up work.
