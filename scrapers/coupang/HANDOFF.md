# Handoff: Coupang collection, first live test

Written 2026-10-16 on Marvin's personal laptop, for a Claude Code session on Marvin's work laptop.
Everything is on `main`. **Delete this file once the work-laptop test is done.**

## The task now

The Chrome extension that collects Coupang has never run live. Marvin is testing it on the work
laptop.

1. **Install.** On the work laptop, Marvin pulls `main` (or clones the repo), then loads the extension
   (a step only Marvin can do): `chrome://extensions` → *Developer mode* → *Load unpacked* → `scrapers\coupang\extension`.
   The Chrome tools can't drive `chrome://` pages. If *Load unpacked* is greyed out, company
   policy blocks it, so the test has to happen on the personal laptop.
2. **Test run.** Marvin clicks the extension's icon → *Test run*. After about a minute, *Recent runs*
   should show (green):
   `<date>_<time> (test): 4 products | product page 3, other page 1, bad input 1 | finished`.
   `Downloads\coupang-snapshots-test\<date>_<time>\` should then hold `products.csv`, four
   `<itemId>_try1.html.gz` and `run.json`.
3. **Convert and compare** (acceptance, spec §13: prices for 3 products match what the page
   shows in a browser).
   - Convert the run into a temporary folder, never into `scrapers/coupang/output/` or `raw/`,
     which are shared with the team.
   - Then open the three product pages in Marvin's Chrome and compare the prices with the
     converted rows.
   - Save this as a file in a scratch folder and run it from the project root by relative path:

   ```r
   source("scrapers/coupang/scrape_coupang.R")
   out <- tempfile("coupang-test")
   saved <- file.path(Sys.getenv("USERPROFILE"), "Downloads", "coupang-snapshots-test")
   result <- import_saved_runs(saved, out_dir = file.path(out, "output"), raw_root = file.path(out, "raw"))
   cat(result$lines, sep = "\n")
   for (file in list.files(file.path(out, "output"), full.names = TRUE)) {
     rows <- read.csv(file, fileEncoding = "UTF-8", colClasses = c(platform_item_id = "character"))
     print(rows[, c("product_id", "fetch_status", "original_price", "sale_price", "extra_price",
                    "extra_price_label", "promo_tag", "seller_type", "in_stock")])
   }
   ```

   `scrape_coupang.R` loads `chromote`, `jsonlite` and `rvest` when it starts, so R 4.6.1 needs
   all three, even for `--saved`.
4. **If it fails.**
   - Read `run.json`: `state`, `error`, and each attempt's `status`, `error` and `block_page`.
   - Ask Marvin for the service worker console: `chrome://extensions` → Coupang snapshots →
     *service worker* → Console.
   - Watch for Save dialogs during the run. If the work laptop's Chrome asks where to save each
     file, `chrome.downloads.download({saveAs: false})` may still prompt; this has not been
     checked.
5. **Afterwards.** Marvin removes the extension from the work laptop, unless that laptop becomes
   the one that collects. Left installed, it also runs at 10:07 from Oct 19 and duplicates the
   personal laptop's runs.

## Where things are

- **Merged into `main`** through PR #1 (merge commit `843c877`, 2026-10-16). The
  `coupang-scraper` branch is deleted. PR #1 had no description and no review.
  - `1fd9a2d`: the scraper.
  - `933e071`: the GitHub-runner finding and Q7.
  - `67a3a6a`: `--saved` and its tests.
  - `5e82f2a`: the extension, the wake task, and the README and spec updates.
- **Read first:**
  - `scrapers/coupang/README.md`: how the runs are collected, setup, why an everyday Chrome,
    and how a page is read.
  - `scrapers/data-collection-spec.md`: §7.3, §8, §9.1, §13, and Q7, which is answered there.
- **`extension/`** (Manifest V3):
  - `background.js`: the service worker (schedule, runs, saving).
  - `lib.js`: pure helpers, loadable in Node (schedule, CSV parsing, the itemId rule, the
    summary line).
  - `popup.*`, `manifest.json`, and `test_products.csv` (the Test run table).
- **`windows/`**: `install_wake_task.ps1` and `wake_for_run.ps1`.
- **`scrape_coupang.R --saved [folder]`** turns saved runs into the spec's files. The old mode,
  which drives its own Chrome through chromote, is kept but unused: Akamai refuses it.
- **`tests/`**: 18 base-R tests (`test_saved_runs.R`, `test_parse_product_page.R`), run from
  the project root by relative path.

## How it works

**Schedule** (Taiwan time): 10:07 daily, Oct 19 to Nov 25, plus 18:07 and 23:07 on Nov 10–12.
It runs from `chrome.alarms`. A slot missed while Chrome was off runs when Chrome is back, on
the same Taiwan day only.

**A run, in order:**
1. Healthchecks `/start` ping.
2. Product table from GitHub `main` (`products/products.csv`). If GitHub can't be reached, it
   uses the last copy downloaded.
3. A minimised window opens on Coupang's home page, which it stays on for 5 s.
4. For each product, a `fetch` with `credentials: 'include'` runs inside that tab (injected with
   `chrome.scripting`): 5 s apart, 30 s timeout.
   - A timeout, 5xx or 429 gets one retry after 60 s.
   - A block (403, Access Denied, 你沒有權限存取此頁面, or the JavaScript check): wait 60 s and
     retry, go back through the home page and retry once more. After 3 blocked products in a
     row, each product gets one try only.
5. Each body is gzipped in the page and saved through `chrome.downloads` (a `data:` URL) as
   `Downloads\coupang-snapshots\<stamp>\<itemId>_try<k>.html.gz`. The download UI is hidden and
   the entries are erased.
6. `run.json` is written last.
7. Success or `/fail` ping, then the popup history and the badge (red `!` when the last study
   run failed).

**Kinds of run:**
- `scheduled`.
- `manual`: *Run now*, for make-ups (spec 9.3).
- `test`: *Test run*. It uses the bundled table and the `-test` folder, does not ping, does
  not change the badge, and uses no slot.

A run cut short (Chrome closed or crashed) is finished as `interrupted` when the extension next
starts.

**`--saved`:**
- Each saved run that has no CSV yet becomes `scrapers/coupang/output/coupang_<stamp>.csv` and
  `raw/<stamp>/<itemId>.html.gz`. Earlier tries are kept as `_1`, `_2`, …
- A run is never converted twice, and a run with no `run.json` yet is skipped.
- It exits 1 when a run has no `ok` row (FR-9).
- It reads `%USERPROFILE%\Downloads\coupang-snapshots`, or `COUPANG_SAVED_DIR`.

**Wake task** "Coupang snapshots wake": installed on the **personal laptop only**.
- Runs at 10:06 daily, plus 18:06 and 23:06 on Nov 10–12, and wakes the laptop.
- Starts Chrome (`--no-startup-window`) if it isn't running.
- Keeps the system and the screen awake until a `run.json` appears, or 45 min.
- Logs to `wake.log` next to the saved runs.
- Needs time zone Taipei and mains power.

## Reference values (Marvin's browser, 2026-10-15; prices drift)

| Test product | Page showed | Expected row |
|---|---|---|
| TEST-001 AirPods 4, itemId 497204175273987 | `8折 $3,590`, struck `$4,490`, `王道卡 特惠價 $3,410` | 4490 / 3590 / 3410 `王道卡 特惠價`, `8折`, platform |
| TEST-002 SWEET TOUCH 2L, itemId 220665340723205 | `0.1折 $1`, struck `$199`, `$198 首購折扣價 · 折扣剩下9小時` | 199 / 199 / 1 `首購折扣價`, `0.1折` |
| TEST-003 CW case, itemId 664996224450656 | `7折 $490`, struck `$700`, sold by 承暉數位科技有限公司 | 700 / 490 / NA, `7折`, marketplace |
| TEST-004, itemId 100000000000001 | HTTP 200 "找不到商品" page | `parse_failure` |
| TEST-005, link without itemId | (not requested) | `bad_input` |

## Rules from Marvin and earlier sessions

- **Never probe Coupang** with curl, httr2, headless Chrome or chromote from Marvin's
  connections: Akamai flags the address, as happened on 2026-10-15. Opening pages in Marvin's normal
  Chrome is fine.
- **No disguising automation** and no solving Akamai's challenges. If the everyday Chrome is
  refused, the product is recorded as `blocked`.
- **Marvin does the account and install steps**: installing extensions, signing up for
  services, anything on `chrome://` pages.
- **Short answers**, verdict first.
- **Keep tests out of the shared files.** Test runs never go into `scrapers/coupang/output/` or
  `raw/`.

## Still to do

1. The work-laptop test (above).
2. **Personal laptop**, which collects and has the wake task:
   - Load the extension and do a Test run there too.
   - Optionally, check the wake from sleep: put the laptop to sleep before a trigger and check
     `wake.log` and the run.
3. **Healthchecks.io** (Marvin signs up):
   - A check with schedule *Cron* `7 10 * * *`, time zone `Asia/Taipei`, grace 1 h. Its ping URL
     goes in the popup's Settings.
   - Optionally a second check, `7 18,23 10-12 11 *`, in the second field.
   - Check the URL once with `curl -fsS <ping url>`.
4. **Product table.** The teammate's `products/products.csv` must be on `main` before Oct 19,
   10:07. It is header-only now, so a run would have 0 products.
5. **The team's OK.** The spec changes (Q7, FR-7, WF-2, NFR-2, NFR-5, D6) reached `main`
   without review, so Marvin still needs to post a heads-up to the team, on PR #1 or in their
   chat.
   - Fixes from the test go on a new branch, through a PR that a teammate reviews. That is the
     team convention from now on: no commits straight to `main`.
6. **During the study:** run `Rscript scrapers/coupang/scrape_coupang.R --saved` from the project
   root, then copy `output/` and `raw/` to the team's storage (Q6).
7. **Not verified yet:**
   - a sold-out page;
   - 11.11 campaign labels (re-check in early November);
   - whether Chrome runs after a timer wake under Modern Standby;
   - a minimised, unfocused window;
   - `.gz` downloads without prompts;
   - the service worker staying alive through a ~10-minute run of about 100 products.
8. `.Renviron` with `SCRAPER_CONTACT` is missing. Only the unused chromote mode needs it.

## Environment notes (personal laptop; the work laptop may differ)

- **Rscript and paths.** Rscript segfaults on an absolute script path containing the apostrophe
  in "Marvin's Laptop", so run scripts by relative path from the project root. `-e` code
  containing `&` also breaks; put it in a file. Rscript is at
  `C:\Program Files\R\R-4.6.1\bin\Rscript.exe` and is not on Git Bash's PATH.
- **Chrome.** One profile; downloads go to `%USERPROFILE%\Downloads` without asking.
- **Chrome tool output.** The Claude in Chrome tools redact output containing query strings or
  cookies, and cut it off at about 2–3 KB.
- **`gh` CLI** is not installed.
- **Skills worth using:** `claude-in-chrome` for the price comparison (load the Chrome tools in
  one ToolSearch call), `tdd` for R changes, and `code-review` before each PR.
