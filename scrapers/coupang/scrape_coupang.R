# Coupang scraper for the Double 11 price study.
#
# Writes one snapshot row per product per run, as defined in scrapers/data-collection-spec.md.
# Run from the project root:
#
#   Rscript scrapers/coupang/scrape_coupang.R [product_table.csv]
#
# Coupang sits behind Akamai Bot Manager, which answers plain HTTP clients (httr2, curl) with 403
# whatever their headers, so every page is loaded in a real Chrome window driven through
# chromote. scrapers/coupang/README.md explains this and the other choices made here.

suppressPackageStartupMessages({
  library(chromote)
  library(jsonlite)
  library(rvest)
})

# ---- Settings ------------------------------------------------------------------------------------

PLATFORM <- "coupang"
PLATFORM_DIR <- file.path("scrapers", PLATFORM)
DEFAULT_PRODUCT_TABLE <- file.path("products", "products.csv")
PROFILE_DIR <- file.path(PLATFORM_DIR, ".chrome-profile")

PACE_SECONDS <- 5          # NFR-1: gap between page loads
TIMEOUT_SECONDS <- 30      # 8.2: per request
RETRY_WAIT_SECONDS <- 60   # 8.2: wait before the one retry, and before each block workaround
SETTLE_SECONDS <- 2        # time on the page after it is ready, as a visitor would stay
RUN_BUDGET_MINUTES <- 38   # stop sending requests before the 45-minute job timeout (WF-7)
MAX_BLOCKED_STREAK <- 3    # after this many products in a row end blocked, skip the long workarounds

INPUT_COLUMNS <- c("product_id", "brand", "model", "category", "momo_url", "pchome_url",
                   "coupang_url", "biggo_url_momo", "biggo_url_pchome", "biggo_url_coupang")
OUTPUT_COLUMNS <- c("date", "scraped_at", "platform", "product_id", "platform_item_id",
                    "original_price", "sale_price", "extra_price", "extra_price_label",
                    "shown_discount_pct", "promo_tag", "coupon_note", "seller_type", "in_stock",
                    "http_status", "source", "fetch_status")
STATUS_ORDER <- c("ok", "parse_failure", "http_error", "timeout", "blocked", "bad_input")

# ---- Small helpers -------------------------------------------------------------------------------

tw_format <- function(time, fmt) format(time, fmt, tz = "Asia/Taipei")

log_line <- function(...) message(PLATFORM, ": ", ...)

fail_start <- function(...) {
  log_line("run not started: ", ...)
  quit(save = "no", status = 1)
}

# Section 7.2: trim, and turn newlines and runs of whitespace (Unicode included) into one space.
clean_text <- function(x) trimws(gsub("(*UCP)\\s+", " ", x, perl = TRUE))

# Section 7.2: "$4,490" -> 4490. Anything that is not a plain whole price gives NA.
parse_price <- function(x) {
  if (length(x) == 0 || is.na(x[1])) return(NA_integer_)
  digits <- gsub("NT\\$|\\$|元|,|\\s", "", x[1])
  if (grepl("^[0-9]+$", digits)) as.integer(digits) else NA_integer_
}

# Joins tags in page order, dropping exact duplicates (7.2). No tags gives NA.
join_tags <- function(x) {
  x <- unique(x[!is.na(x) & nzchar(x)])
  if (length(x) == 0) NA_character_ else paste(x, collapse = " | ")
}

# ---- Input: the product table (section 6) --------------------------------------------------------

read_product_table <- function(path) {
  if (!file.exists(path)) fail_start("product table not found: ", path)
  table <- tryCatch(
    read.csv(path, fileEncoding = "UTF-8-BOM", colClasses = "character",
             na.strings = character(), check.names = FALSE),
    error = function(e) fail_start("cannot read product table ", path, ": ", conditionMessage(e))
  )
  missing <- setdiff(INPUT_COLUMNS, names(table))
  if (length(missing) > 0) {
    fail_start("product table ", path, " is missing column(s): ", paste(missing, collapse = ", "))
  }
  table
}

is_coupang_link <- function(url) {
  grepl("^https?://([a-z0-9-]+\\.)*coupang\\.com(:[0-9]+)?([/?#]|$)", url, ignore.case = TRUE)
}

# The itemId query parameter of a coupang.com link, or NA. Tracking parameters are ignored.
extract_item_id <- function(url) {
  url <- trimws(url)
  if (!is_coupang_link(url)) return(NA_character_)
  query <- if (grepl("?", url, fixed = TRUE)) sub("^[^?]*\\?", "", url) else ""
  query <- gsub("&amp;", "&", sub("#.*$", "", query), fixed = TRUE)
  for (pair in strsplit(query, "&", fixed = TRUE)[[1]]) {
    kv <- strsplit(pair, "=", fixed = TRUE)[[1]]
    if (length(kv) == 2 && kv[1] == "itemId" && grepl("^[0-9]+$", kv[2])) return(kv[2])
  }
  NA_character_
}

# One row per product with a Coupang link, in file order (6.2), with the reason it is bad (6.3).
select_products <- function(table) {
  ids <- trimws(table$product_id)
  urls <- trimws(table$coupang_url)
  keep <- nzchar(urls)
  targets <- data.frame(
    line = which(keep) + 1L,  # line in the CSV file, counting the header as line 1
    product_id = ids[keep],
    url = urls[keep],
    stringsAsFactors = FALSE
  )
  targets$item_id <- vapply(targets$url, extract_item_id, "", USE.NAMES = FALSE)
  targets$problem <- NA_character_
  targets$problem[is.na(targets$item_id)] <- "no itemId found in coupang_url"
  targets$problem[!is_coupang_link(targets$url)] <- "coupang_url is not a coupang.com link"
  targets$problem[targets$product_id %in% ids[duplicated(ids)]] <- "product_id appears more than once"
  targets$problem[!nzchar(targets$product_id)] <- "product_id is empty"
  targets
}

# ---- Output (section 7) --------------------------------------------------------------------------

new_row <- function(run_date, target, fetch_status, http_status = NA_integer_, scraped_at = NA,
                    fields = list()) {
  row <- data.frame(
    date = run_date,
    scraped_at = if (inherits(scraped_at, "POSIXt")) tw_format(scraped_at, "%Y-%m-%d %H:%M:%S") else NA_character_,
    platform = PLATFORM,
    product_id = target$product_id,
    platform_item_id = target$item_id,
    original_price = NA_integer_,
    sale_price = NA_integer_,
    extra_price = NA_integer_,
    extra_price_label = NA_character_,
    shown_discount_pct = NA_real_,
    promo_tag = NA_character_,
    coupon_note = NA_character_,
    seller_type = NA_character_,
    in_stock = NA,
    http_status = as.integer(http_status),
    source = "scraper",
    fetch_status = fetch_status,
    stringsAsFactors = FALSE
  )
  for (name in names(fields)) if (length(fields[[name]]) == 1) row[[name]] <- fields[[name]]
  row[OUTPUT_COLUMNS]
}

# The file is claimed with its header when the run starts, so a second run in the same minute
# stops before sending anything (FR-4), and each row is added as soon as its product is done, so
# a run killed part-way still leaves the rows it finished. The result is what write.csv() writes.
write_rows <- function(rows, path, header) {
  write.table(rows, path, append = !header, col.names = header, row.names = FALSE, sep = ",",
              dec = ".", qmethod = "double", na = "NA", fileEncoding = "UTF-8")
}

claim_output_file <- function(path) {
  empty <- new_row("", list(product_id = "", item_id = NA_character_), "")[0, ]
  write_rows(empty, path, header = TRUE)
}

# FR-5: every main-document response body, gzip-compressed. The body the row was read from is
# <item>.html.gz; earlier ones for the same product (challenge pages, failed tries) are numbered.
save_raw_bodies <- function(bodies, raw_dir, item_id) {
  if (length(bodies) == 0) return(invisible())
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  files <- c(sprintf("%s_%d.html.gz", item_id, seq_len(length(bodies) - 1)),
             sprintf("%s.html.gz", item_id))
  for (i in seq_along(bodies)) {
    con <- gzfile(file.path(raw_dir, files[i]), "wb")
    writeBin(charToRaw(enc2utf8(bodies[[i]])), con)
    close(con)
  }
}

summary_line <- function(rows, out_file) {
  counts <- table(factor(rows$fetch_status, levels = STATUS_ORDER))
  counts <- counts[counts > 0]
  counts <- counts[order(-counts, match(names(counts), STATUS_ORDER))]
  parts <- if (length(counts) == 0) "nothing to do" else paste(names(counts), counts, collapse = ", ")
  sprintf("%s: %d products | %s | %s", PLATFORM, nrow(rows), parts, out_file)
}

# ---- Browser -------------------------------------------------------------------------------------

# Reports what the tab is showing: still loading, Akamai's JavaScript check, or a product page.
PAGE_STATE_JS <- r"---[(() => {
  const ld = Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
    .some(s => /"@type"\s*:\s*"Product"/.test(s.textContent));
  return JSON.stringify({
    ready: document.readyState,
    challenge: !!document.getElementById('sec-if-cpt-container'),
    product: ld
  });
})()]---"

# A normal (not headless) Chrome window with its own profile in scrapers/coupang/.chrome-profile
# (git-ignored), so cookies carry over from page to page and run to run, as for a person
# browsing. `fresh = TRUE` deletes the profile first: a new visitor with no history.
browser_open <- function(fresh = FALSE) {
  if (fresh) unlink(PROFILE_DIR, recursive = TRUE)
  dir.create(PROFILE_DIR, recursive = TRUE, showWarnings = FALSE)
  profile <- normalizePath(PROFILE_DIR)
  port_file <- file.path(profile, "DevToolsActivePort")
  unlink(c(port_file, file.path(profile, c("SingletonLock", "SingletonCookie", "SingletonSocket"))))

  proxy <- Sys.getenv("SCRAPER_PROXY")
  args <- c(
    "--remote-debugging-port=0", paste0("--user-data-dir=", profile),
    "--no-first-run", "--no-default-browser-check", "--lang=zh-TW", "--window-size=1366,900",
    # keep the page running normally when the window is behind others
    "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
    "--disable-backgrounding-occluded-windows",
    if (Sys.info()[["sysname"]] == "Linux" && nzchar(Sys.getenv("CI"))) "--no-sandbox",
    if (nzchar(proxy)) paste0("--proxy-server=", proxy),
    "about:blank"
  )
  proc <- processx::process$new(chromote::find_chrome(), args, stdout = NULL, stderr = NULL,
                                supervise = TRUE)
  port <- NA_integer_
  for (i in 1:100) {
    if (file.exists(port_file)) {
      port <- suppressWarnings(as.integer(readLines(port_file, n = 1, warn = FALSE)[1]))
    }
    if (!is.na(port) || !proc$is_alive()) break
    Sys.sleep(0.2)
  }
  if (is.na(port)) {
    proc$kill_tree()
    stop("Chrome did not start (", chromote::find_chrome(), ")")
  }

  br <- new.env()
  br$proc <- proc
  br$cm <- Chromote$new(browser = ChromeRemote$new(host = "127.0.0.1", port = port))
  tab <- Filter(function(t) identical(t$type, "page"), br$cm$Target$getTargets()$targetInfos)[[1]]
  # Attaching to Chrome's own tab (rather than a new one) keeps the window's real viewport.
  br$session <- ChromoteSession$new(parent = br$cm, targetId = tab$targetId)
  br$frame_id <- br$session$Page$getFrameTree()$frameTree$frame$id
  br$broken <- FALSE
  reset_navigation(br)

  # Every main-document response of the current navigation, in order, with its body.
  session <- br$session
  session$Network$enable()
  session$Network$requestWillBeSent(callback = function(m) {
    if (identical(m$type, "Document") && identical(m$frameId, br$frame_id)) {
      br$doc_ids <- union(br$doc_ids, m$requestId)
    }
  })
  session$Network$responseReceived(callback = function(m) {
    if (m$requestId %in% br$doc_ids) {
      br$docs[[m$requestId]] <- list(status = as.integer(m$response$status),
                                     url = m$response$url, body = NULL, done = FALSE)
    }
  })
  session$Network$loadingFinished(callback = function(m) {
    id <- m$requestId
    if (!is.null(br$docs[[id]])) {
      session$Network$getResponseBody(requestId = id, wait_ = FALSE)$then(
        function(b) {
          body <- if (isTRUE(b$base64Encoded)) rawToChar(base64_dec(b$body)) else b$body
          Encoding(body) <- "UTF-8"
          br$docs[[id]]$body <- body
          br$docs[[id]]$done <- TRUE
        },
        function(e) br$docs[[id]]$done <- TRUE
      )
    }
  })
  session$Network$loadingFailed(callback = function(m) {
    if (m$requestId %in% br$doc_ids) {
      br$nav_error <- m$errorText
      if (!is.null(br$docs[[m$requestId]])) br$docs[[m$requestId]]$done <- TRUE
    }
  })
  br
}

reset_navigation <- function(br) {
  br$doc_ids <- character()
  br$docs <- list()
  br$nav_error <- NULL
}

browser_close <- function(br) {
  if (is.null(br)) return(invisible())
  # A clean shutdown lets Chrome write its cookies to the profile for the next run.
  try(br$cm$Browser$close(wait_ = FALSE), silent = TRUE)
  try(br$proc$wait(10000), silent = TRUE)
  if (br$proc$is_alive()) br$proc$kill_tree()
  try(br$cm$close(), silent = TRUE)
  invisible()
}

page_state <- function(session) {
  res <- tryCatch(session$Runtime$evaluate(PAGE_STATE_JS, returnByValue = TRUE, timeout_ = 5),
                  error = function(e) NULL)
  value <- res$result$value
  if (!is.null(res$exceptionDetails) || !is.character(value)) return(NULL)
  fromJSON(value)
}

# Loads one URL and waits until the tab holds a final page: a product page, an error or block
# page, or nothing after TIMEOUT_SECONDS. Akamai's JavaScript check reloads the page by itself,
# so a check page is waited out rather than taken as the answer.
browser_fetch <- function(br, url) {
  reset_navigation(br)
  sent_at <- Sys.time()
  deadline <- sent_at + TIMEOUT_SECONDS
  nav <- tryCatch(br$session$Page$navigate(url, timeout_ = TIMEOUT_SECONDS),
                  error = function(e) list(errorText = conditionMessage(e)))
  if (!is.null(nav$errorText)) br$nav_error <- nav$errorText

  state <- NULL
  quiet_since <- NULL
  repeat {
    state <- page_state(br$session)
    status <- last_doc(br)$status
    final <- FALSE
    if (!is.null(state) && !isTRUE(state$challenge)) {
      if (isTRUE(state$product) && state$ready == "complete") {
        final <- TRUE
      } else if (!is.null(status) && status >= 400 && state$ready != "loading") {
        final <- TRUE
      } else if (state$ready == "complete") {
        # Not a product page: give a script-driven redirect two seconds to start.
        if (is.null(quiet_since)) quiet_since <- Sys.time()
        final <- difftime(Sys.time(), quiet_since, units = "secs") >= 2
      }
    }
    if (length(br$docs) == 0 && !is.null(br$nav_error)) final <- TRUE
    if (final || Sys.time() > deadline) break
    Sys.sleep(0.25)
  }
  if (isTRUE(state$product)) Sys.sleep(SETTLE_SECONDS)

  # Wait briefly for the last response bodies to arrive.
  for (i in 1:20) {
    if (all(vapply(br$docs, function(d) d$done, TRUE))) break
    try(br$session$Runtime$evaluate("1", timeout_ = 5), silent = TRUE)
    Sys.sleep(0.25)
  }
  last <- last_doc(br)
  list(
    sent_at = sent_at,
    status = if (is.null(last)) NA_integer_ else last$status,
    body = last$body,
    bodies = Filter(Negate(is.null), lapply(br$docs, function(d) d$body)),
    challenge = isTRUE(state$challenge),
    error = br$nav_error
  )
}

last_doc <- function(br) if (length(br$docs) == 0) NULL else br$docs[[length(br$docs)]]

# ---- Parsing (section 7.3) -----------------------------------------------------------------------
#
# Everything is read from the HTML as the server sent it (the body saved under raw/), so a saved
# page can be parsed again later. Prices come from the page's JSON-LD where it carries them, and
# from the price block (.price-container) and the card-offer list otherwise.

PRICE_RE <- "^(NT)?\\$[0-9][0-9,]*$"
ZHE_RE <- "^[0-9]+(\\.[0-9]+)?折$"
PCT_RE <- "^-?[0-9]+(\\.[0-9]+)?%$"
SOLD_OUT_RE <- "已售完|暫時缺貨|已停售|已下架|商品不存在|無法購買"

# Access Denied pages, Coupang's own 403 page and Akamai's JavaScript check (8.1: blocked).
is_block_page <- function(html) {
  grepl("<title>Access Denied</title>|errors\\.edgesuite\\.net|id=\"error403\"|sec-if-cpt-container",
        html, ignore.case = TRUE)
}

# The schema.org Product object from the page's JSON-LD, or NULL.
product_json_ld <- function(doc) {
  for (txt in html_text(html_elements(doc, "script[type='application/ld+json']"))) {
    obj <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
    candidates <- if (!is.null(obj[["@graph"]])) obj[["@graph"]] else if (is.null(names(obj))) obj else list(obj)
    for (x in candidates) if (identical(x[["@type"]], "Product")) return(x)
  }
  NULL
}

# Each element's own text inside `node`, in page order, with its class attribute. Text from
# separate page elements stays in separate pieces; joined, they are separated by one space.
text_pieces <- function(node) {
  els <- xml2::xml_find_all(node, ".//*[not(self::script) and not(self::style)][text()[normalize-space()]]")
  own <- vapply(els, function(e) paste(xml2::xml_text(xml2::xml_find_all(e, "./text()")), collapse = ""), "")
  data.frame(text = clean_text(own), class = xml2::xml_attr(els, "class", default = ""),
             stringsAsFactors = FALSE)
}

# The price block: headline price, struck-through price, 折 or % badge, and the line under the
# headline that explains a conditional reduction, e.g. "$198 首購折扣價 · 折扣剩下9小時".
read_price_block <- function(block) {
  p <- text_pieces(block)
  is_price <- grepl(PRICE_RE, p$text)
  struck <- is_price & grepl("(^| )twc-line-through( |$)", p$class)
  badge <- grepl(ZHE_RE, p$text) | grepl(PCT_RE, p$text)
  unit <- grepl("^\\(.*\\)$", p$text)  # unit price, e.g. "($0.05/100ml)"
  head_i <- which(is_price & !struck)[1]
  last_main <- suppressWarnings(max(head_i, which(struck)[1], na.rm = TRUE))
  after <- seq_len(nrow(p)) > last_main & !badge & !unit
  labels <- p$text[after & !is_price]
  list(
    headline = parse_price(p$text[head_i]),
    struck = parse_price(p$text[which(struck)[1]]),
    zhe = p$text[grepl(ZHE_RE, p$text)],
    pct = p$text[grepl(PCT_RE, p$text)],
    condition_label = labels[grepl("價$", labels)][1],
    condition_amount = parse_price(p$text[after & is_price][1]),
    condition_line = if (any(after)) paste(p$text[after], collapse = " ") else NA_character_
  )
}

# The entries listed under a heading such as 刷卡優惠 or 銀行回饋, as text pieces.
offer_entries <- function(doc, heading) {
  head <- xml2::xml_find_first(doc, sprintf("//div[normalize-space(text())='%s']", heading))
  if (inherits(head, "xml_missing")) return(list())
  box <- xml2::xml_find_first(head, "following-sibling::div[1]")
  entries <- xml2::xml_find_all(box, ".//li[not(ancestor::li)]")
  lapply(entries, text_pieces)
}

# Card prices from 刷卡優惠 entries: the card name, then "特惠價" followed by the price.
card_prices <- function(entries) {
  rows <- lapply(entries, function(p) {
    i <- which(grepl("價$", p$text) & c(grepl(PRICE_RE, p$text[-1]), FALSE))[1]
    if (is.na(i)) return(NULL)
    data.frame(label = paste(p$text[seq_len(i)], collapse = " "), price = parse_price(p$text[i + 1]),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# Reads one product page. Returns list(found, fields, note): `found` is FALSE when the page shows
# neither a sale price nor a sold-out notice (parse_failure); `fields` are output columns.
parse_product_page <- function(html) {
  doc <- read_html(html)
  ld <- product_json_ld(doc)
  block <- html_element(doc, ".price-container")
  has_block <- !inherits(block, "xml_missing")
  if (is.null(ld) && !has_block) {
    if (grepl(SOLD_OUT_RE, clean_text(html_text(html_element(doc, "body"))))) {
      return(list(found = TRUE, fields = list(in_stock = FALSE), note = "removed or sold-out page"))
    }
    return(list(found = FALSE, note = "no product data on the page"))
  }

  offers <- ld$offers
  if (!is.null(offers) && is.null(names(offers))) offers <- offers[[1]]
  specs <- offers$priceSpecification
  if (!is.null(names(specs))) specs <- list(specs)
  ld_struck <- NA_integer_
  for (s in specs) {
    if (grepl("StrikethroughPrice$", s$priceType %||% "")) ld_struck <- parse_price(s$price)
  }
  ld_price <- parse_price(offers$price)
  availability <- sub(".*/", "", offers$availability %||% "")

  pb <- if (has_block) read_price_block(block) else read_price_block(read_html("<p></p>"))
  headline <- if (!is.na(ld_price)) ld_price else pb$headline
  original <- if (!is.na(ld_struck)) ld_struck else pb$struck
  notes <- character()
  if (!is.na(ld_price) && !is.na(pb$headline) && ld_price != pb$headline) {
    notes <- c(notes, sprintf("JSON-LD price %d differs from the price shown (%d)", ld_price, pb$headline))
  }

  # A labelled reduction under the headline (e.g. 首購折扣價) means the headline itself is a
  # conditional price. The unconditional price is then the struck price, but only when the
  # page's own figures show the reduction is the whole gap (headline + amount = struck price).
  sale <- headline
  conditional <- data.frame(label = character(), price = integer(), stringsAsFactors = FALSE)
  if (!is.na(pb$condition_label) && !is.na(headline)) {
    conditional <- data.frame(label = pb$condition_label, price = headline, stringsAsFactors = FALSE)
    covers_gap <- !is.na(original) && !is.na(pb$condition_amount) &&
      headline + pb$condition_amount == original
    sale <- if (covers_gap) original else NA_integer_
    if (!covers_gap) {
      notes <- c(notes, sprintf("headline is a %s price and the price without it is not shown",
                                pb$condition_label))
    }
  }

  cards <- offer_entries(doc, "刷卡優惠")
  conditional <- rbind(conditional, card_prices(cards))
  conditional <- conditional[!is.na(conditional$price), , drop = FALSE]
  lowest <- if (nrow(conditional) > 0) conditional[which.min(conditional$price), ] else NULL

  benefit_box <- html_element(doc, ".conditional-benefits")
  benefits <- if (inherits(benefit_box, "xml_missing")) list() else
    lapply(xml2::xml_children(benefit_box), text_pieces)
  coupon_texts <- vapply(c(benefits, cards, offer_entries(doc, "銀行回饋")),
                         function(p) paste(p$text, collapse = " "), "")

  seller_box <- html_element(doc, ".seller-info")
  rocket <- has_block && length(html_elements(block, "[data-badge-id='ROCKET']")) > 0
  seller_type <- if (!inherits(seller_box, "xml_missing") && grepl("賣家", html_text(seller_box))) {
    "marketplace"
  } else if (rocket) "platform" else NA_character_

  in_stock <- if (nzchar(availability)) {
    availability %in% c("InStock", "LimitedAvailability", "OnlineOnly", "InStoreOnly")
  } else {
    !grepl(SOLD_OUT_RE, clean_text(html_text(html_element(doc, ".prod-atf-contents"))))
  }

  fields <- list(
    original_price = original,
    sale_price = sale,
    extra_price = if (is.null(lowest)) NA_integer_ else as.integer(lowest$price),
    extra_price_label = if (is.null(lowest)) NA_character_ else lowest$label,
    shown_discount_pct = if (length(pb$pct) > 0) abs(as.numeric(sub("%$", "", pb$pct[1]))) else NA_real_,
    promo_tag = join_tags(pb$zhe),
    coupon_note = join_tags(c(pb$condition_line, coupon_texts)),
    seller_type = seller_type,
    in_stock = in_stock
  )
  list(found = !is.na(sale) || !in_stock, fields = fields,
       note = if (length(notes) > 0) paste(notes, collapse = "; ") else NULL)
}

# ---- One product (section 8) ---------------------------------------------------------------------

# What one page load amounts to, before any retry or workaround. `retry` marks the failures that
# get the one retry of 8.2 (429, 5xx, timeout or connection error).
judge_page <- function(page) {
  status <- page$status
  if (is.na(status)) return(list(kind = "timeout", retry = TRUE))
  if (status == 429) return(list(kind = "blocked", retry = TRUE))
  if (status == 403 || page$challenge || (!is.null(page$body) && is_block_page(page$body))) {
    return(list(kind = "blocked", retry = FALSE))
  }
  if (status >= 500) return(list(kind = "http_error", retry = TRUE))
  if (status < 200 || status >= 300) return(list(kind = "http_error", retry = FALSE))
  if (is.null(page$body)) return(list(kind = "parse_failure", retry = FALSE, note = "response body unreadable"))
  parsed <- tryCatch(parse_product_page(page$body),
                     error = function(e) list(found = FALSE, note = paste("parser error:", conditionMessage(e))))
  list(kind = if (parsed$found) "ok" else "parse_failure", retry = FALSE, fields = parsed$fields,
       note = parsed$note)
}

# Loads a page in the run's Chrome, starting (or restarting) Chrome when needed.
load_page <- function(run, url) {
  if (is.null(run$br) || isTRUE(run$br$broken)) {
    browser_close(run$br)
    run$br <- tryCatch(browser_open(), error = function(e) {
      log_line("cannot start Chrome: ", conditionMessage(e))
      NULL
    })
  }
  nothing <- list(sent_at = NA, status = NA_integer_, body = NULL, bodies = list(), challenge = FALSE)
  if (is.null(run$br)) return(nothing)
  sent_at <- Sys.time()
  tryCatch(browser_fetch(run$br, url), error = function(e) {
    log_line("Chrome stopped responding: ", conditionMessage(e))
    run$br$broken <- TRUE
    modifyList(nothing, list(sent_at = sent_at))
  })
}

# NFR-1: at least PACE_SECONDS between page loads, retries included.
pace <- function(run) {
  if (is.null(run$last_load)) return(invisible())
  wait <- PACE_SECONDS - as.numeric(difftime(Sys.time(), run$last_load, units = "secs"))
  if (wait > 0) Sys.sleep(wait)
}

scrape_product <- function(run, target) {
  bodies <- list()
  attempt <- function() {
    pace(run)
    page <- load_page(run, target$url)
    run$last_load <- Sys.time()
    bodies <<- c(bodies, page$bodies)
    list(page = page, verdict = judge_page(page))
  }
  status_text <- function(a) sprintf("%s (HTTP %s)", a$verdict$kind, a$page$status)

  a <- attempt()
  if (a$verdict$retry) {
    log_line(target$product_id, ": ", status_text(a), ", retrying in ", RETRY_WAIT_SECONDS, " s")
    Sys.sleep(RETRY_WAIT_SECONDS)
    a <- attempt()
  }
  # 8.2: a block is worked around before the product counts as blocked: back off, then come back
  # as a new visitor. Once several products in a row end blocked, the run stops doing this, so a
  # site that refuses everything is not hit again and again (each product still gets one load).
  if (a$verdict$kind == "blocked" && run$blocked_streak < MAX_BLOCKED_STREAK) {
    log_line(target$product_id, ": ", status_text(a), ", backing off ", RETRY_WAIT_SECONDS, " s")
    Sys.sleep(RETRY_WAIT_SECONDS)
    a <- attempt()
    if (a$verdict$kind == "blocked") {
      log_line(target$product_id, ": still blocked, restarting Chrome with a fresh profile")
      browser_close(run$br)
      run$br <- tryCatch(browser_open(fresh = TRUE), error = function(e) NULL)
      Sys.sleep(RETRY_WAIT_SECONDS)
      a <- attempt()
    }
  }
  run$blocked_streak <- if (a$verdict$kind == "blocked") run$blocked_streak + 1 else 0
  if (!is.null(a$verdict$note)) log_line(target$product_id, ": ", a$verdict$note)

  save_raw_bodies(bodies, run$raw_dir, target$item_id)
  new_row(run$date, target, a$verdict$kind, http_status = a$page$status,
          scraped_at = a$page$sent_at,
          fields = if (a$verdict$kind == "ok") a$verdict$fields else list())
}

# ---- Run -----------------------------------------------------------------------------------------

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  started <- Sys.time()
  run_date <- tw_format(started, "%Y-%m-%d")
  run_stamp <- paste0(run_date, "_", tw_format(started, "%H%M"))

  if (!file.exists(file.path(PLATFORM_DIR, "scrape_coupang.R"))) {
    fail_start("run it from the project root: Rscript scrapers/coupang/scrape_coupang.R")
  }
  if (!nzchar(Sys.getenv("SCRAPER_CONTACT"))) {
    fail_start("SCRAPER_CONTACT is not set; add it to .Renviron in the project root (NFR-2)")
  }
  table <- read_product_table(if (length(args) >= 1) args[[1]] else DEFAULT_PRODUCT_TABLE)
  if (Sys.info()[["sysname"]] == "Linux" && !nzchar(Sys.getenv("DISPLAY"))) {
    fail_start("Chrome needs a display; on a server run the scraper under xvfb-run")
  }

  out_dir <- file.path(PLATFORM_DIR, "output")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(PLATFORM_DIR, "raw"), recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, sprintf("%s_%s.csv", PLATFORM, run_stamp))
  if (file.exists(out_file)) fail_start(out_file, " already exists; a run already started this minute")
  claim_output_file(out_file)

  targets <- select_products(table)
  for (i in which(!is.na(targets$problem))) {
    log_line("bad input on line ", targets$line[i], " (", targets$product_id[i], "): ", targets$problem[i])
  }

  run <- new.env()
  run$date <- run_date
  run$raw_dir <- file.path(PLATFORM_DIR, "raw", run_stamp)
  run$blocked_streak <- 0
  on.exit(browser_close(run$br), add = TRUE)
  budget_end <- started + RUN_BUDGET_MINUTES * 60

  rows <- vector("list", nrow(targets))
  for (i in seq_len(nrow(targets))) {
    target <- targets[i, ]
    rows[[i]] <- if (!is.na(target$problem)) {
      new_row(run_date, target, "bad_input")
    } else if (Sys.time() > budget_end) {
      # Out of time before the job limit: recorded as not answered, no request sent.
      log_line(target$product_id, ": not requested, run time budget used up")
      new_row(run_date, target, "timeout")
    } else {
      tryCatch(scrape_product(run, target), error = function(e) {
        log_line(target$product_id, ": unexpected error: ", conditionMessage(e))
        new_row(run_date, target, "timeout")
      })
    }
    write_rows(rows[[i]], out_file, header = FALSE)
    log_line(sprintf("[%d/%d] %s %s: %s", i, nrow(targets), target$product_id, target$item_id,
                     rows[[i]]$fetch_status))
  }
  browser_close(run$br)
  run$br <- NULL

  all_rows <- if (length(rows) > 0) do.call(rbind, rows) else new_row("", list(product_id = "", item_id = NA), "")[0, ]
  cat(summary_line(all_rows, out_file), "\n", sep = "")
  quit(save = "no", status = if (any(all_rows$fetch_status == "ok")) 0 else 1)
}

if (sys.nframe() == 0L) main()
