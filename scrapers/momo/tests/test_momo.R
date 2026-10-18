#!/usr/bin/env Rscript
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- dirname(dirname(dirname(dirname(normalizePath(sub("^--file=", "", script_arg[[1L]]), winslash = "/", mustWork = TRUE)))))
.libPaths(c(file.path(root, ".R-library"), .libPaths()))
source(file.path(root, "scrapers", "momo", "momo.R"), encoding = "UTF-8")
checks <- 0L
check <- function(value, label) {
  if (!isTRUE(value)) stop("FAIL: ", label)
  checks <<- checks + 1L
  cat("PASS: ", label, "\n", sep = "")
}
must_fail <- function(expr) inherits(tryCatch(force(expr), error = function(e) e), "error")
product <- list(product_id = "TEST-001", momo_i_code = "123", momo_variant_sku = "001",
  momo_variant_label = "Single 24 pack", momo_expected_title = "Test drink 330ml x24")
fixture <- function(conditional = TRUE, options = 1L, currency = "TWD", schema_price = NULL,
                    missing_sale = FALSE, title = product$momo_expected_title,
                    coupon = "查看可使用的折價券", sold_out = FALSE) {
  offer_price <- if (is.null(schema_price)) if (conditional) "233" else "275" else schema_price
  variants <- lapply(seq_len(options), function(i) list("@type" = "Product", sku = sprintf("%03d", i),
    name = "Single 24 pack", offers = list("@type" = "Offer", price = offer_price, priceCurrency = currency)))
  schema <- jsonlite::toJSON(list("@graph" = list(list("@type" = "ProductGroup", sku = "123",
    name = title, hasVariant = variants))), auto_unbox = TRUE)
  price <- function(label, amount) paste0('<div><span>', label,
    '</span><span class="font-price"><span>$</span><span>', amount, '</span></span><span>元</span></div>')
  ordinary <- if (missing_sale) "" else price("促銷價", "275")
  primary <- if (conditional) price("限時折後價", "233") else ordinary
  strike <- paste0(if (conditional) ordinary else "", price("市售價", "299"))
  html <- paste0('<html><head><title>Test</title><script type="application/ld+json">', schema,
    '</script></head><body><div id="purchase"><div data-testid="goods-info">',
    '<div data-testid="goods-code-info">品號：123</div><span>美食單件85折</span><span>滿1件享85折</span>',
    '</div><div data-testid="web-goods-price-container"><div data-testid="price-main-container">',
    '<div data-testid="price-primary-row">', primary, '</div><div data-testid="price-strike-row">',
    strike, '</div></div></div><button>', coupon, '</button>',
    if (sold_out) "<span>已售完</span>" else "", '</div></body></html>')
  charToRaw(enc2utf8(html))
}
parsed <- momo_parse(fixture(), product)
check(identical(parsed$original_price, 299L) && identical(parsed$sale_price, 275L) &&
  identical(parsed$extra_price, 233L), "Keep market, ordinary selling and conditional prices separate")
check(identical(parsed$extra_price_label, "限時折後價") &&
  grepl("滿1件享85折", parsed$promo_tag, fixed = TRUE) &&
  is.na(parsed$shown_discount_pct), "Copy Chinese labels; do not calculate a percent from 85折")
ordinary <- momo_parse(fixture(FALSE), product)
check(identical(ordinary$sale_price, 275L) && is.na(ordinary$extra_price),
  "An ordinary headline is not an extra discount")
check(must_fail(momo_parse(fixture(options = 2L), product)), "Reject multiple options instead of choosing the default")
check(must_fail(momo_parse(fixture(title = "Test drink 330ml x48"), product)), "Reject changed pack size/title")
check(must_fail(momo_parse(fixture(currency = "USD"), product)), "Reject foreign currency")
check(must_fail(momo_parse(fixture(schema_price = "199"), product)), "Reject schema/headline disagreement")
check(must_fail(momo_parse(fixture(missing_sale = TRUE), product)), "Never use conditional JSON-LD price as missing ordinary price")
check(must_fail(momo_money("$233–275")), "Reject price ranges rather than merging their digits")
check(identical(momo_money("NT$1,200元"), 1200L), "Parse whole NT$ amounts")
check(!momo_parse(fixture(sold_out = TRUE), product)$in_stock, "Record explicit sold-out notice")
check(momo_challenge(charToRaw("<title>Access Denied</title>")), "Recognise an access challenge")
check(!momo_is_sold_out(charToRaw(enc2utf8("<html><body>網頁無法顯示。可能的原因是：商品目前無展售 網頁不存在</body></html>"))),
  "A generic error page listing possible causes is not a confirmed removed product")


check(identical(momo_parse(fixture(), list(momo_i_code = "123"))$sale_price, 275L),
  "URL-only product metadata is sufficient for supported single-option pages")
check(identical(momo_extract_id("https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=123&utm_source=team"), "123"),
  "Extract legacy i_code while stripping tracking")
check(identical(momo_extract_id("https://www.momoshop.com.tw/product/123?osm=test"), "123"),
  "Accept canonical product links with tracking")
check(is.na(momo_extract_id("https://evil.example/product/123")) &&
  is.na(momo_extract_id("https://www.momoshop.com.tw/search?keyword=test")),
  "Reject other hosts and search-result URLs")
check(is.na(momo_extract_id("https://www.momoshop.com.tw/product/123?i_code=456")),
  "Reject contradictory path and query listing IDs")
temp_root <- tempfile("momo-integration-")
dir.create(temp_root)
make_table <- function(ids, urls, name = "products.csv") {
  x <- as.data.frame(setNames(rep(list(rep("", length(ids))), length(momo_input_columns)),
    momo_input_columns), stringsAsFactors = FALSE)
  x$product_id <- ids
  x$brand <- "Test"
  x$model <- "Test drink 330ml x24"
  x$category <- "FOOD"
  x$momo_url <- urls
  path <- file.path(temp_root, name)
  write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
  path
}
urls <- c("https://www.momoshop.com.tw/search?keyword=test",
  "https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=123&utm_source=x",
  "https://www.momoshop.com.tw/product/456", "https://www.momoshop.com.tw/product/789",
  "https://www.momoshop.com.tw/product/123", "https://www.momoshop.com.tw/product/123", "")
path <- make_table(c("BAD", "GOOD", "MISSING", "SOLDOUT", "DUP", "DUP", "SKIP"), urls)
products <- momo_read_products(path)
check(nrow(products) == 6L && sum(products$momo_bad_input) == 3L,
  "Duplicate IDs and bad links become row errors; blank momo links are excluded")
check(identical(products$momo_url[[2L]], "https://www.momoshop.com.tw/product/123"),
  "Request a rebuilt product URL without tracking parameters")
check(must_fail(momo_read_products(file.path(temp_root, "absent.csv"))), "Missing product table cannot start")
bad_schema <- file.path(temp_root, "bad-schema.csv")
writeLines("product_id,momo_url\nTEST,https://www.momoshop.com.tw/product/123", bad_schema)
check(must_fail(momo_read_products(bad_schema)), "Missing input columns cannot start")
calls <- character()
run_started <- as.POSIXct("2026-10-18 23:59:59", tz = "Asia/Taipei")
mock_fetch <- function(url, browser_agent = FALSE) {
  calls <<- c(calls, url)
  body <- if (grepl("/123$", url)) fixture() else if (grepl("/789$", url))
    charToRaw(enc2utf8("<html><body><main>商品已下架</main></body></html>")) else charToRaw("<html><body>Not found</body></html>")
  list(status = 200L, body = body, received = TRUE, error = NULL,
    sent_at = run_started + length(calls))
}
platform <- file.path(temp_root, "platform")
result <- momo_collect(products, platform, "test@example.com", fetch = mock_fetch,
  run_started = run_started, sleep = function(seconds) NULL)
check(length(calls) == 3L && identical(result$rows$fetch_status,
  c("bad_input", "ok", "parse_failure", "ok", "bad_input", "bad_input")),
  "Bad input and missing listing do not block later valid or removed products")
check(identical(names(result$rows), momo_columns) && ncol(result$rows) == 17L,
  "New shared output has exactly 17 columns including fetch_status")
check(all(result$rows$date == "2026-10-18") && grepl("2026-10-19", result$rows$scraped_at[[2L]]),
  "Run date stays fixed across midnight; request timestamps use actual Taiwan time")
check(all(is.na(result$rows$scraped_at[result$rows$fetch_status == "bad_input"])),
  "Unrequested rows have NA scraped_at and HTTP status")
check(result$rows$http_status[[3L]] == 200L && is.na(result$rows$sale_price[[3L]]) &&
  is.na(result$rows$in_stock[[3L]]), "A 200 not-found page is parse_failure with NA prices and stock")
check(!result$rows$in_stock[[4L]] && result$exit_status == 0L,
  "Removed notice is ok/out-of-stock; any ok row gives exit zero")
saved <- read.csv(result$output, na.strings = "NA", fileEncoding = "UTF-8", check.names = FALSE)
check(identical(saved$extra_price_label[[2L]], "限時折後價"), "Chinese text survives shared CSV write/read")
check(basename(result$output) == "momo_2026-10-18_2359.csv",
  "Use the shared per-run filename")
hash <- tools::md5sum(result$output)
before <- length(calls)
check(must_fail(momo_collect(products, platform, "test@example.com", fetch = mock_fetch,
  run_started = run_started, sleep = function(seconds) NULL)) && length(calls) == before &&
  identical(tools::md5sum(result$output), hash),
  "A second run in the same minute sends no requests and preserves the first file")
files <- list.files(result$raw_dir)
check(all(c("123.html.gz", "456.html.gz", "789.html.gz") %in% files) &&
  !any(grepl("BAD|DUP", files)), "Archive every response, never unrequested rows")
con <- gzfile(file.path(result$raw_dir, "123.html.gz"), "rb")
bytes <- readBin(con, "raw", 1000000L)
close(con)
check(identical(bytes, fixture()), "Raw gzip preserves exact response bytes")

one <- products[products$product_id == "GOOD", , drop = FALSE]
waits <- numeric()
statuses <- c(500L, 200L)
retry_fetch <- function(url, browser_agent = FALSE) {
  status <- statuses[[1L]]
  statuses <<- statuses[-1L]
  list(status = status, body = if (status == 200L) fixture() else charToRaw("Server error"),
    received = TRUE, error = NULL, sent_at = run_started)
}
retry <- momo_collect(one, file.path(temp_root, "retry"), "test@example.com", retry_fetch,
  run_started, sleep = function(seconds) waits <<- c(waits, seconds))
check(identical(waits, 60) && retry$rows$fetch_status == "ok" &&
  all(c("123__attempt1.html.gz", "123.html.gz") %in% list.files(retry$raw_dir)),
  "Retry a 5xx once after 60 seconds and preserve both response bodies")

blocked_fetch <- function(url, browser_agent = FALSE) list(status = 403L, body = charToRaw("Forbidden"),
  received = TRUE, error = NULL, sent_at = run_started)
blocked <- momo_collect(one, file.path(temp_root, "blocked"), "test@example.com", blocked_fetch,
  run_started, sleep = function(seconds) NULL)
check(blocked$rows$fetch_status == "blocked" && blocked$rows$http_status == 403L &&
  blocked$exit_status == 1L, "Exhausted block is a row failure with exit one when none is ok")
timeout_fetch <- function(url, browser_agent = FALSE) list(status = NA_integer_, body = raw(),
  received = FALSE, error = "Connection timed out", sent_at = run_started)
timeout <- momo_collect(one, file.path(temp_root, "timeout"), "test@example.com", timeout_fetch,
  run_started, sleep = function(seconds) NULL)
check(timeout$rows$fetch_status == "timeout" && is.na(timeout$rows$http_status) &&
  !file.exists(file.path(timeout$raw_dir, "123.html.gz")), "No response means timeout and no raw response file")
check(must_fail(momo_collect(one, file.path(temp_root, "no-contact"), "", mock_fetch,
  run_started, sleep = function(seconds) NULL)) &&
  !dir.exists(file.path(temp_root, "no-contact")), "Missing SCRAPER_CONTACT prevents a run before requests/output")

test_products <- momo_read_products(file.path(root, "scrapers", "momo", "tests", "products_test.csv"))
check(nrow(test_products) == 7L && !any(test_products$momo_bad_input), "Seven real verification links use the team's standard URL-only schema")
unlink(temp_root, recursive = TRUE)
cat(sprintf("All %d checks passed; no network requests made.\n", checks))
