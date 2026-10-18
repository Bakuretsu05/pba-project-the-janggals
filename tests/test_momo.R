#!/usr/bin/env Rscript
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- dirname(dirname(normalizePath(sub("^--file=", "", script_arg[[1L]]), winslash = "/", mustWork = TRUE)))
.libPaths(c(file.path(root, ".R-library"), .libPaths()))
source(file.path(root, "scraper", "momo.R"), encoding = "UTF-8")
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

policy <- momo_robots(paste(
  "User-agent: *", "Disallow: /api/*", "Disallow: /*?*utm_", "Disallow: /private",
  "Allow: /private/public", "Crawl-delay: 7", sep = "\n"))
check(policy$allowed("/product/123") && !policy$allowed("/api/prices") &&
  !policy$allowed("/product/123?utm_source=x") && policy$allowed("/private/public"),
  "Respect robots wildcards, query rules and longest-path allow")
check(policy$delay == 7, "Respect crawl delay greater than five seconds")
specific <- momo_robots("User-agent: *\nDisallow: /\nUser-agent: PBA-Double11-study\nAllow: /product/\nDisallow: /product/no")
check(specific$allowed("/product/123") && !specific$allowed("/product/no"),
  "Select the matching study-specific robots group")
check(!momo_robots("<html>Something went wrong</html>")$valid,
  "Do not treat a 200 HTML error response as a valid robots policy")

products <- data.frame(product_id = c("TEST-001", "TEST-002"),
  momo_i_code = c("123", "456"), momo_url = c("https://www.momoshop.com.tw/product/123",
    "https://www.momoshop.com.tw/product/456"),
  momo_expected_title = product$momo_expected_title, momo_variant_sku = "001",
  momo_variant_label = "Single 24 pack", stringsAsFactors = FALSE)
temp_root <- tempfile("momo-recorder-test-")
dir.create(temp_root)
on.exit_cleanup <- function() unlink(temp_root, recursive = TRUE)
mock_time <- as.POSIXct("2026-10-18 10:00:00", tz = "Asia/Taipei")
calls <- character()
mock_fetch <- function(url) {
  calls <<- c(calls, url)
  if (grepl("robots.txt", url, fixed = TRUE))
    return(list(status = 200L, body = charToRaw("User-agent: *\nAllow: /"), requested = TRUE, blocked = FALSE))
  if (grepl("/456$", url))
    return(list(status = 404L, body = charToRaw("not found"), requested = TRUE, blocked = FALSE))
  list(status = 200L, body = fixture(), requested = TRUE, blocked = FALSE,
    headers = list("content-type" = "text/html"))
}
out_dir <- file.path(temp_root, "snapshots")
raw_dir <- file.path(temp_root, "raw")
log_dir <- file.path(temp_root, "logs")
first <- momo_run(products[2:1, ], out_dir, raw_dir, log_dir, mock_fetch, now = function() mock_time)
check(first$attempted == 2L && first$success == 1L, "An HTTP 404 produces a row and does not stop the next product")
data <- read.csv(first$output, fileEncoding = "UTF-8", na.strings = "NA", check.names = FALSE)
check(identical(names(data), momo_columns) && data$http_status[[1L]] == 404L &&
  is.na(data$sale_price[[1L]]) && is.na(data$in_stock[[1L]]), "Exact 16 columns; failed row retains HTTP status and NA values")
check(identical(data$extra_price_label[[2L]], "限時折後價"), "UTF-8 Chinese survives CSV write/read")
second <- momo_run(products[1L, , drop = FALSE], out_dir, raw_dir, log_dir, mock_fetch, now = function() mock_time)
data <- read.csv(second$output, fileEncoding = "UTF-8", na.strings = "NA")
lines <- readLines(second$output, encoding = "UTF-8")
check(nrow(data) == 3L && sum(grepl('^"date",', lines)) == 1L, "Same-day rerun appends without a duplicate header")
captures <- list.files(file.path(raw_dir, "momo", "2026-10-18"), pattern = "^123[.]html[.]gz$", recursive = TRUE, full.names = TRUE)
check(length(captures) == 3L, "Preserve canonical capture plus both timestamped run captures")
con <- gzfile(captures[[1L]], "rb")
recovered <- readBin(con, "raw", 1000000L)
close(con)
check(identical(recovered, fixture()), "Raw gzip round-trips exact response bytes")
events <- lapply(readLines(second$log, encoding = "UTF-8"), jsonlite::fromJSON)
check(any(vapply(events, function(x) identical(x$http_status, 404L), logical(1))), "Audit log records failed request")
calls <- character()
blocked_fetch <- function(url) {
  calls <<- c(calls, url)
  if (grepl("robots.txt", url, fixed = TRUE))
    return(list(status = 200L, body = charToRaw("User-agent: *\nAllow: /"), requested = TRUE, blocked = FALSE))
  list(status = 403L, body = charToRaw("Forbidden"), requested = TRUE, blocked = TRUE)
}
blocked <- momo_run(products, file.path(temp_root, "blocked-out"), raw_dir, log_dir,
  blocked_fetch, now = function() mock_time)
blocked_rows <- read.csv(blocked$output, na.strings = "NA")
check(length(calls) == 2L && blocked$attempted == 1L && blocked$stopped &&
  nrow(blocked_rows) == 2L && blocked_rows$http_status[[1L]] == 403L &&
  is.na(blocked_rows$http_status[[2L]]), "403 stops subsequent requests and distinguishes blocked from unrequested rows")
calls <- character()
bad_robots_fetch <- function(url) {
  calls <<- c(calls, url)
  list(status = 200L, body = charToRaw("<html>Error</html>"), requested = TRUE,
    blocked = FALSE, error = "robots.txt did not contain a valid user-agent group")
}
bad_robots <- momo_run(products, file.path(temp_root, "bad-robots-out"), raw_dir, log_dir,
  bad_robots_fetch, now = function() mock_time)
bad_robots_rows <- read.csv(bad_robots$output, na.strings = "NA")
check(length(calls) == 1L && bad_robots$attempted == 0L && bad_robots$stopped &&
  nrow(bad_robots_rows) == 2L && all(is.na(bad_robots_rows$http_status)),
  "An invalid robots response stops all product requests and records unrequested rows")
actual <- momo_read_products(file.path(root, "data", "products.csv"))
queue <- jsonlite::fromJSON(file.path(root, "data", "momo-review-queue.json"))
check(nrow(actual) == 7L && queue$pending_count == 93L &&
  !any(actual$product_id %in% queue$products$product_id), "Seven confirmed inputs and 93 pending products are disjoint")
on.exit_cleanup()
cat(sprintf("All %d checks passed; no network requests made.\n", checks))

