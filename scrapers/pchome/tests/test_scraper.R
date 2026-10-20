source("scrapers/pchome/scrape_pchome.R", encoding = "UTF-8")

passed <- 0L
failed <- character()
test <- function(name, code) {
  tryCatch({
    force(code)
    passed <<- passed + 1L
    cat("PASS ", name, "\n", sep = "")
  }, error = function(error) {
    failed <<- c(failed, name)
    cat("FAIL ", name, ": ", conditionMessage(error), "\n", sep = "")
  })
}
expect_error <- function(code, pattern) {
  problem <- tryCatch({ force(code); NULL }, error = conditionMessage)
  stopifnot(!is.null(problem), grepl(pattern, problem))
}

item_id <- "ABCDEF-A12345678"
item_url <- paste0("https://24h.pchome.com.tw/prod/", item_id)
page_html <- function(sale = 100L, original = 150L, conditional = NULL, stock = TRUE,
                       id = item_id, terms = "限時活動 任選1件$90") {
  headline <- if (is.null(conditional)) sale else conditional
  main <- paste0('<div class="c-prodPrice"><div class="c-prodPrice__price">$', headline, '</div>')
  if (!is.null(conditional)) main <- paste0('<div class="c-prodPrice"><div class="c-prodPrice__title">折扣價</div>',
    '<div class="c-prodPrice__price">$', headline, '</div>')
  if (is.null(conditional) && !is.null(original)) main <- paste0(main,
    '<div class="c-prodPrice__originalPrice">$', original, '</div>')
  main <- paste0(main, '</div>')
  if (!is.null(conditional)) main <- paste0(main,
    '<div class="c-prodPrice"><div class="c-prodPrice__title">網路價</div>',
    '<div class="c-prodPrice__originalPrice">$', sale, '</div></div>')
  paste0('<html><body><div data-regression="prod_info" data-gtm-item_id="', id, '">',
    '<div class="c-boxGrid__item--prodBriefingArea"><h1>中文測試商品</h1>',
    '<div class="o-prodMainName__colorPrimary300">超越保濕 直達肌底修復力</div>',
    '<div data-regression="prod_promoTag"><span class="c-label__text">期間限定優惠</span></div>',
    if (!is.null(conditional)) paste0('<div data-regression="prod_discount">',
      '<a class="c-discountEvent__link">', terms, '</a></div>') else '',
    '<div data-regression="prod_price">', main, '</div>',
    '<div data-regression="prod_info_ship">PChome 倉庫出貨，24小時到貨</div>',
    if (stock) '<button data-regression="product_button_buyNow">立即購買</button>' else '<div>暫時缺貨</div>',
    '<script>{"Price":{"M":336,"P":285,"Low":275}}</script>',
    '</div></div><div class="c-prodPrice__price">$99999</div></body></html>')
}
response <- function(status = 200L, body = page_html(), retry_after = NULL) {
  list(status = status, body = charToRaw(enc2utf8(body)), retry_after = retry_after)
}
product_table <- function(urls = item_url, ids = if (length(urls)) paste0("TEST-", seq_along(urls)) else character()) {
  rows <- as.data.frame(setNames(rep(list(rep("", length(urls))), length(INPUT_COLUMNS)),
                                INPUT_COLUMNS), stringsAsFactors = FALSE)
  rows$product_id <- ids
  rows$pchome_url <- urls
  rows$model <- rep("中文測試商品", length(urls))
  rows
}
exercise <- function(table = product_table(), responses = list(response()), contact = "tests@example.invalid",
                     browser = NULL) {
  folder <- tempfile("pchome-test-")
  dir.create(folder)
  input <- file.path(folder, "products.csv")
  write.csv(table, input, row.names = FALSE, fileEncoding = "UTF-8", na = "")
  state <- new.env()
  state$now <- as.POSIXct("2026-10-16 15:59:58", tz = "UTC")
  state$sent <- numeric()
  state$waits <- numeric()
  state$calls <- 0L
  state$agents <- character()
  clock <- function() state$now
  wait <- function(seconds) {
    state$waits <- c(state$waits, seconds)
    state$now <- state$now + seconds
  }
  requested <- unique(na.omit(vapply(table$pchome_url, extract_item_id, character(1))))
  serve <- function(url, agent) {
    state$calls <- state$calls + 1L
    state$sent <- c(state$sent, as.numeric(state$now))
    state$agents <- c(state$agents, agent)
    stopifnot(url %in% product_url(requested))
    current <- responses[[min(state$calls, length(responses))]]
    if (inherits(current, "condition")) stop(current)
    if (is.function(current)) return(current(url, agent))
    current
  }
  transport <- function(url, user_agent) {
    stopifnot(user_agent %in% c(paste0("PBA-Double11-study (NTHU ISS4066; contact: ", contact, ")"),
                                BROWSER_USER_AGENT))
    serve(url, user_agent)
  }
  # browser = TRUE stands in for headless Chrome; its loads are recorded as "headless".
  loader <- if (isTRUE(browser)) function(url) serve(url, "headless")
  result <- run_scraper(input, contact, file.path(folder, "pchome"), transport, clock, wait, loader)
  list(result = result, state = state, folder = folder, input = input,
       clock = clock, wait = wait, transport = transport)
}
read_body <- function(path) {
  connection <- gzfile(path, "rb")
  on.exit(close(connection))
  readBin(connection, "raw", n = 1e7)
}

test("tracking parameters and explicit variant suffix", {
  stopifnot(identical(extract_item_id(paste0(item_url, "?utm_source=test#price")), item_id),
            identical(extract_item_id(paste0(item_url, "-001")), paste0(item_id, "-001")),
            is.na(extract_item_id("https://evil.example/prod/ABCDEF-A12345678")),
            is.na(extract_item_id("https://24h.pchome.com.tw.evil.example/prod/ABCDEF-A12345678")))
})
test("whole prices reject malformed numbers", {
  stopifnot(whole_price("NT$4,490元") == 4490L, is.na(whole_price("12.5")),
            is.na(whole_price(-5)), is.na(whole_price(1e20)), is.na(whole_price(NULL)))
})
test("visible HTML prices and equal crossed-out price are preserved", {
  parsed <- parse_product_page(response()$body, item_id)
  stopifnot(parsed$fetch_status == "ok", parsed$sale_price == 100L,
            parsed$original_price == 150L, parsed$in_stock)
  stopifnot(parse_product_page(response(body = page_html(original = 100))$body,
                              item_id)$original_price == 100L)
})
test("API-only prices never become page observations", {
  parsed <- parse_product_page(charToRaw('[{"Seq":"","Price":{"M":336,"P":285},"Qty":0}]'), item_id)
  stopifnot(parsed$fetch_status == "parse_failure")
})
test("missing displayed price versus explicit sold-out notice", {
  stopifnot(parse_product_page(response(body = page_html(sale = NA, original = NULL))$body,
                              item_id)$fetch_status == "parse_failure")
  sold <- parse_product_page(response(body = page_html(sale = NA, original = NULL, stock = FALSE))$body, item_id)
  stopifnot(sold$fetch_status == "ok", identical(sold$in_stock, FALSE), is.na(sold$sale_price))
})
test("page identity and unverified selected variants are rejected", {
  stopifnot(parse_product_page(response()$body, "ZZZZZZ-A12345678")$fetch_status == "parse_failure",
            parse_product_page(response()$body, paste0(item_id, "-001"))$fetch_status == "parse_failure")
})
test("invalid and non-product responses fail parsing", {
  for (body in c("<html>maintenance</html>", "[]", "{}", "null", "123", "[null]")) {
    stopifnot(parse_product_page(charToRaw(body), item_id)$fetch_status == "parse_failure")
  }
})
test("soy milk discrepancy uses displayed 285 and 275, never internal 336", {
  parsed <- parse_product_page(response(body = page_html(sale = 285, conditional = 275,
    terms = "限時活動 10/14 - 10/31 任選1件$275"))$body, item_id)
  stopifnot(parsed$fetch_status == "ok", parsed$sale_price == 285L,
            parsed$original_price == 285L, parsed$extra_price == 275L,
            parsed$extra_price_label == "限時活動 10/14 - 10/31 任選1件$275",
            is.na(parsed$shown_discount_pct))
})
test("unshown and non-struck reference prices remain NA", {
  body <- page_html(original = NULL)
  stopifnot(is.na(parse_product_page(charToRaw(enc2utf8(body)), item_id)$original_price))
  body <- sub('class="c-prodPrice__originalPrice"',
              'class="c-prodPrice__originalPrice" style="text-decoration: none"', page_html(), fixed = TRUE)
  stopifnot(is.na(parse_product_page(charToRaw(enc2utf8(body)), item_id)$original_price))
})
test("unverified conditional prices never become unconditional sale prices", {
  body <- page_html(sale = 285, conditional = 275, terms = "限時活動")
  parsed <- parse_product_page(charToRaw(enc2utf8(body)), item_id)
  stopifnot(parsed$sale_price == 285L, is.na(parsed$extra_price), is.na(parsed$extra_price_label),
            grepl("could not be linked", parsed$verification_note))
  body <- gsub("網路價", "未知價格", body, fixed = TRUE)
  stopifnot(parse_product_page(charToRaw(enc2utf8(body)), item_id)$fetch_status == "parse_failure")
})
test("lowest explicitly labelled conditional amount is selected without arithmetic", {
  body <- page_html(sale = 285, conditional = 275, terms = "任選1件$275")
  body <- sub('<div data-regression="prod_price">', paste0(
    '<div data-regression="prod_discount"><a class="c-discountEvent__link">會員價$250</a></div>',
    '<div data-regression="prod_price"><div class="c-prodPrice">',
    '<div class="c-prodPrice__title">會員價</div><div class="c-prodPrice__price">$250</div></div>'),
    body, fixed = TRUE)
  parsed <- parse_product_page(charToRaw(enc2utf8(body)), item_id)
  stopifnot(parsed$sale_price == 285L, parsed$extra_price == 250L,
            parsed$extra_price_label == "會員價$250")
})
test("hidden prices and recommendation cards do not contaminate the product", {
  body <- sub('<div data-regression="prod_price">', paste0('<div data-regression="prod_price">',
    '<span hidden class="c-prodPrice__price">$999</span>',
    '<span style="display: none" class="c-prodPrice__originalPrice">$999</span>'),
    page_html(), fixed = TRUE)
  parsed <- parse_product_page(charToRaw(enc2utf8(body)), item_id)
  stopifnot(parsed$sale_price == 100L, parsed$original_price == 150L)
})
test("discount badges are copied, fold badges are not converted, cashback is not a discount", {
  for (badge in c("-23%", "85折")) {
    body <- sub('</h1>', paste0('</h1><div data-regression="prod_discount"><span class="c-label__text">',
      badge, '</span></div><div data-regression="prod_promoText">6%</div>'), page_html(), fixed = TRUE)
    parsed <- parse_product_page(charToRaw(enc2utf8(body)), item_id)
    stopifnot(grepl(badge, parsed$promo_tag, fixed = TRUE))
    if (badge == "-23%") stopifnot(parsed$shown_discount_pct == 23) else stopifnot(is.na(parsed$shown_discount_pct))
  }
})
test("the seller's slogan above the product name is not a promo tag", {
  parsed <- parse_product_page(charToRaw(enc2utf8(page_html())), item_id)
  stopifnot(identical(parsed$promo_tag, "期間限定優惠"))
})
test("24h pages are sold by PChome and a shown price without a sold-out notice is in stock", {
  body <- sub("PChome 倉庫出貨，24小時到貨", "配送資訊未提供", page_html(), fixed = TRUE)
  body <- sub('<button data-regression="product_button_buyNow">立即購買</button>', '', body, fixed = TRUE)
  parsed <- parse_product_page(charToRaw(enc2utf8(body)), item_id)
  stopifnot(parsed$fetch_status == "ok", parsed$seller_type == "platform", isTRUE(parsed$in_stock))
})
test("challenge words in scripts or noscript never block a product page", {
  body <- sub('<script>', paste0('<noscript>JavaScript is required. 網頁載入中</noscript>',
    '<script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script><script>grecaptcha;'),
    page_html(), fixed = TRUE)
  stopifnot(!is_challenge(charToRaw(enc2utf8(body))),
            is_challenge(charToRaw("<html><body>Access Denied</body></html>")),
            is_challenge(charToRaw('<html><div id="sec-if-cpt-container"></div></html>')))
})
test("sold-out wording in a gift promotion does not override enabled product purchase buttons", {
  body <- sub('</h1>', '</h1><div data-regression="prod_promoText">贈品已售完</div>', page_html(), fixed = TRUE)
  stopifnot(parse_product_page(charToRaw(enc2utf8(body)), item_id)$in_stock)
})
test("each successful row has explicit limited-coverage evidence", {
  run <- exercise()
  audit <- read.csv(file.path(run$result$raw_dir, "verification.csv"), fileEncoding = "UTF-8")
  stopifnot(audit$price_source == "customer_visible_html", audit$coverage == "visible_text_only",
            grepl("unverified", audit$verification_note))
})
test("exact schema, NA encoding, Chinese input and gzip byte preservation", {
  run <- exercise()
  saved <- read.csv(run$result$output, fileEncoding = "UTF-8", check.names = FALSE)
  stopifnot(identical(names(saved), OUTPUT_COLUMNS), nrow(saved) == 1L,
            is.na(saved$extra_price), saved$promo_tag == "期間限定優惠", saved$sale_price == 100L,
            identical(read_products(run$input)$model, "中文測試商品"),
            identical(read_body(list.files(run$result$raw_dir, full.names = TRUE, pattern = "gz$")), response()$body))
  stopifnot(grepl(",NA,", readLines(run$result$output, encoding = "UTF-8")[2], fixed = TRUE))
  text_row <- run$result$data
  text_row$promo_tag <- "中文測試標籤"
  text_path <- file.path(run$folder, "encoding-check.csv")
  write.csv(text_row, text_path, row.names = FALSE, na = "NA", fileEncoding = "UTF-8")
  stopifnot(identical(read.csv(text_path, fileEncoding = "UTF-8")$promo_tag, "中文測試標籤"))
})
test("missing contact and missing input columns send no requests", {
  expect_error(exercise(contact = ""), "SCRAPER_CONTACT")
  expect_error(exercise(table = product_table()[, -1]), "Missing input columns")
  expect_error(read_products("does-not-exist.csv"), "not found")
})
test("UTF-8 BOM input preserves all rows and Chinese text", {
  run <- exercise()
  bytes <- readBin(run$input, "raw", n = file.info(run$input)$size)
  writeBin(c(as.raw(c(239, 187, 191)), bytes), run$input)
  stopifnot(identical(read_products(run$input)$model, "中文測試商品"))
})
test("malformed rows continue, duplicate product IDs all fail, empty links skip", {
  table <- product_table(c("not a link", item_url, item_url, "", item_url),
                          c("BAD", "DUP", "DUP", "SKIP", "GOOD"))
  run <- exercise(table)
  stopifnot(identical(run$result$data$fetch_status, c("bad_input", "bad_input", "bad_input", "ok")),
            run$state$calls == 1L, all(is.na(run$result$data$scraped_at[1:3])))
})
test("HTTP 404 and parse failure continue to next valid product", {
  run <- exercise(product_table(rep(item_url, 3)),
                  list(response(404L), response(body = "[]"), response()))
  stopifnot(identical(run$result$data$fetch_status, c("http_error", "parse_failure", "ok")),
            identical(run$result$data$http_status, c(404L, 200L, 200L)),
            all(is.na(run$result$data$sale_price[1:2])), run$result$exit_code == 0L,
            length(list.files(run$result$raw_dir, pattern = "gz$")) == 3L, all(diff(run$state$sent) >= 5))
})
test("one retry, sixty-second delay and every response saved", {
  run <- exercise(responses = list(response(503L), response()))
  stopifnot(run$state$calls == 2L, diff(run$state$sent) >= 60,
            run$result$data$fetch_status == "ok", length(list.files(run$result$raw_dir, pattern = "gz$")) == 2L)
  # FR-5: the body the row was read from carries the plain name.
  stopifnot(identical(read_body(file.path(run$result$raw_dir, paste0(item_id, ".html.gz"))), response()$body),
            identical(read_body(file.path(run$result$raw_dir, paste0(item_id, "__attempt1.html.gz"))),
                      response(503L)$body))
  run <- exercise(responses = list(response(503L)))
  stopifnot(run$state$calls == 2L, run$result$data$fetch_status == "http_error",
            is.na(run$result$data$sale_price), run$result$exit_code == 1L)
})
test("connection errors retry once and never create a response file", {
  run <- exercise(responses = list(simpleError("connection failed")))
  stopifnot(run$state$calls == 2L, diff(run$state$sent) >= 60,
            run$result$data$fetch_status == "timeout", is.na(run$result$data$http_status),
            length(list.files(run$result$raw_dir, pattern = "gz$")) == 0L)
})
test("real httr2 refused local connection is recorded as timeout", {
  local_failure <- function(url, user_agent) http_get("http://127.0.0.1:1/", user_agent)
  run <- exercise(responses = list(local_failure))
  stopifnot(run$state$calls == 2L, run$result$data$fetch_status == "timeout",
            length(list.files(run$result$raw_dir, pattern = "gz$")) == 0L)
})
test("last failed retry has NA HTTP status even after a 503", {
  run <- exercise(responses = list(response(503L), simpleError("connection failed")))
  stopifnot(run$result$data$fetch_status == "timeout", is.na(run$result$data$http_status),
            length(list.files(run$result$raw_dir, pattern = "gz$")) == 1L)
})
test("a 403 or challenge is worked around as a browser, then in headless Chrome", {
  for (blocked in list(response(403L), response(body = "<html>Access Denied</html>"))) {
    run <- exercise(responses = list(blocked, response()))
    stopifnot(run$result$data$fetch_status == "ok", run$state$calls == 2L,
              identical(run$state$agents[2], BROWSER_USER_AGENT), diff(run$state$sent) >= 60)
    run <- exercise(responses = list(blocked, blocked, response()), browser = TRUE)
    stopifnot(run$result$data$fetch_status == "ok", identical(run$state$agents[3], "headless"),
              length(list.files(run$result$raw_dir, pattern = "gz$")) == 3L)
  }
})
test("a product blocked by every workaround is blocked, and the run moves on", {
  other_url <- "https://24h.pchome.com.tw/prod/ZZZZZZ-A12345678"
  serve <- function(url, agent) if (grepl(item_id, url, fixed = TRUE)) response(403L) else
    response(body = page_html(id = "ZZZZZZ-A12345678"))
  run <- exercise(product_table(c(item_url, other_url)), list(serve), browser = TRUE)
  stopifnot(identical(run$result$data$fetch_status, c("blocked", "ok")),
            run$result$data$http_status[1] == 403L, !is.na(run$result$data$scraped_at[1]),
            run$state$calls == 4L, run$result$exit_code == 0L)
})
test("after three products in a row end blocked, later products get one request", {
  ids <- paste0("ABCDE", 1:5, "-A12345678")
  run <- exercise(product_table(paste0("https://24h.pchome.com.tw/prod/", ids)),
                  list(response(429L)), browser = TRUE)
  stopifnot(all(run$result$data$fetch_status == "blocked"), run$state$calls == 3 * 4 + 2,
            all(run$result$data$http_status == 429L))
})
test("Retry-After is honoured up to its cap", {
  run <- exercise(responses = list(response(429L, retry_after = "90"), response()))
  stopifnot(run$result$data$fetch_status == "ok", run$state$calls == 2L, diff(run$state$sent) >= 90)
  run <- exercise(responses = list(response(429L, retry_after = "86400"), response()))
  stopifnot(run$result$data$fetch_status == "ok", max(run$state$waits) == MAX_RETRY_AFTER_SECONDS)
})
test("summary line lists only the statuses that occurred", {
  rows <- data.frame(fetch_status = c("ok", "ok", "blocked"))
  stopifnot(identical(summary_line(rows, "out.csv"), "pchome: 3 products | ok 2, blocked 1 | out.csv"))
})
test("an interrupted run that saved nothing frees its minute", {
  run <- exercise()
  platform_dir <- file.path(run$folder, "again")
  expect_error(run_scraper(run$input, "tests@example.invalid", platform_dir,
                           function(url, user_agent) stop("connection failed"), run$clock,
                           function(seconds) stop("interrupted"), NULL), "interrupted")
  stopifnot(length(list.files(file.path(platform_dir, "raw"))) == 0L)
})
test("same-minute collision preserves CSV and raw bytes and sends no requests", {
  run <- exercise()
  before <- readBin(run$result$output, "raw", n = 1e7)
  expect_error(run_scraper(run$input, "tests@example.invalid", file.path(run$folder, "pchome"),
                          run$transport, run$clock, run$wait), "already exists")
  stopifnot(identical(before, readBin(run$result$output, "raw", n = 1e7)), run$state$calls == 1L)
})
test("run date is frozen across Taiwan midnight and later runs create new files", {
  run <- exercise(product_table(rep(item_url, 2)))
  stopifnot(all(run$result$data$date == "2026-10-16"),
            run$result$data$scraped_at[1] == "2026-10-16 23:59:58",
            run$result$data$scraped_at[2] == "2026-10-17 00:00:03")
  run$state$now <- run$state$now + 60
  next_run <- run_scraper(run$input, "tests@example.invalid", file.path(run$folder, "pchome"),
                          run$transport, run$clock, run$wait)
  stopifnot(next_run$output != run$result$output, file.exists(run$result$output),
            all(next_run$data$date == "2026-10-17"))
})
test("empty main table writes a header and exits one", {
  run <- exercise(product_table(character()))
  stopifnot(run$result$exit_code == 1L, run$state$calls == 0L,
            identical(names(read.csv(run$result$output)), OUTPUT_COLUMNS))
})

cat("\n", passed, " passed, ", length(failed), " failed\n", sep = "")
quit(save = "no", status = if (length(failed)) 1L else 0L)
