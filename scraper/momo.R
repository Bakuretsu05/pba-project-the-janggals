# Shared implementation for the public momo product-page recorder.
if (.Platform$OS.type == "windows" && !isTRUE(l10n_info()[["UTF-8"]]))
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
momo_columns <- c("date", "scraped_at", "platform", "product_id", "platform_item_id",
  "original_price", "sale_price", "extra_price", "extra_price_label",
  "shown_discount_pct", "promo_tag", "coupon_note", "seller_type", "in_stock",
  "http_status", "source")

momo_text <- function(node) {
  if (length(node) == 0L || inherits(node, "xml_missing")) return(NA_character_)
  value <- trimws(rvest::html_text2(node))
  if (!nzchar(value)) NA_character_ else value
}
momo_join <- function(values) {
  values <- unique(values[!is.na(values) & nzchar(values)])
  if (length(values)) paste(values, collapse = " | ") else NA_character_
}
momo_money <- function(value) {
  if (length(value) != 1L || is.na(value)) return(NA_integer_)
  value <- trimws(gsub("NT\\$|\\$|元|,", "", value))
  if (!grepl("^[0-9]+$", value)) stop("Ambiguous/non-integer price: ", value)
  result <- suppressWarnings(as.integer(value))
  if (is.na(result)) stop("Price outside supported integer range")
  result
}
momo_challenge <- function(body) {
  text <- tryCatch(rawToChar(body), error = function(e) "")
  grepl("Access Denied|Just a moment|cf-chl-|challenge-platform|g-recaptcha|驗證您是人類|安全驗證",
    text, ignore.case = TRUE, perl = TRUE)
}

# Parse robots groups, selecting the most specific matching user-agent group.
momo_robots <- function(text, agent = "PBA-Double11-study") {
  groups <- list()
  current <- list(agents = character(), rules = list(), delay = 0)
  rules_started <- FALSE
  flush <- function() {
    if (length(current$agents)) groups[[length(groups) + 1L]] <<- current
  }
  for (line in strsplit(text, "\n", fixed = TRUE)[[1L]]) {
    line <- trimws(sub("#.*$", "", line))
    colon <- regexpr(":", line, fixed = TRUE)[1L]
    if (colon < 1L) next
    key <- tolower(trimws(substr(line, 1L, colon - 1L)))
    value <- trimws(substr(line, colon + 1L, nchar(line)))
    if (key == "user-agent") {
      if (rules_started) {
        flush()
        current <- list(agents = character(), rules = list(), delay = 0)
        rules_started <- FALSE
      }
      current$agents <- c(current$agents, tolower(value))
    } else if (length(current$agents) && key %in% c("allow", "disallow", "crawl-delay")) {
      rules_started <- TRUE
      if (key == "crawl-delay") {
        delay <- suppressWarnings(as.numeric(value))
        if (is.finite(delay) && delay >= 0) current$delay <- max(current$delay, delay)
      } else if (nzchar(value)) {
        current$rules[[length(current$rules) + 1L]] <- list(allow = key == "allow", path = value)
      }
    }
  }
  flush()
  specificity <- vapply(groups, function(g) {
    matched <- g$agents[vapply(g$agents, function(a)
      a == "*" || grepl(a, tolower(agent), fixed = TRUE), logical(1))]
    if (!length(matched)) -1L else max(ifelse(matched == "*", 0L, nchar(matched)))
  }, integer(1))
  selected <- groups[specificity == max(c(-1L, specificity)) & specificity >= 0L]
  rules <- unlist(lapply(selected, function(g) g$rules), recursive = FALSE)
  delay <- max(c(5, vapply(selected, function(g) g$delay, numeric(1))))
  allowed <- function(path) {
    matches <- lapply(rules, function(rule) {
      chars <- strsplit(rule$path, "", fixed = TRUE)[[1L]]
      regex <- paste0(vapply(seq_along(chars), function(i) {
        ch <- chars[[i]]
        if (ch == "*") ".*" else if (ch == "$" && i == length(chars)) "$"
        else if (ch %in% c(".", "+", "?", "^", "$", "(", ")", "[", "]", "{", "}", "|", "\\")) paste0("\\", ch)
        else ch
      }, character(1)), collapse = "")
      if (grepl(paste0("^", regex), path, perl = TRUE))
        list(allow = rule$allow, length = nchar(gsub("*", "", rule$path, fixed = TRUE)))
      else NULL
    })
    matches <- Filter(Negate(is.null), matches)
    if (!length(matches)) return(TRUE)
    longest <- max(vapply(matches, function(x) x$length, integer(1)))
    any(vapply(matches, function(x) x$length == longest && x$allow, logical(1)))
  }
  list(allowed = allowed, delay = delay, valid = length(groups) > 0L)
}

momo_product_group <- function(doc, code) {
  groups <- list()
  for (node in rvest::html_elements(doc, 'script[type="application/ld+json"]')) {
    parsed <- tryCatch(jsonlite::fromJSON(rvest::html_text(node), simplifyVector = FALSE),
      error = function(e) NULL)
    walk <- function(x) {
      if (!is.list(x)) return()
      if ("ProductGroup" %in% unlist(x[["@type"]]) &&
          identical(as.character(x$sku), code)) groups[[length(groups) + 1L]] <<- x
      for (child in x) if (is.list(child)) walk(child)
    }
    walk(parsed)
  }
  if (length(groups) != 1L) stop("Expected one ProductGroup for requested item ID")
  groups[[1L]]
}

momo_parse <- function(body, product) {
  if (momo_challenge(body)) stop("Challenge page")
  doc <- xml2::read_html(body)
  code <- as.character(product$momo_i_code)
  group <- momo_product_group(doc, code)
  title <- group$name
  if (!identical(title, product$momo_expected_title))
    stop("Product title changed; review exact model, formula, size and pack count")
  code_text <- momo_text(rvest::html_element(doc, '[data-testid="goods-code-info"]'))
  if (is.na(code_text) || !identical(gsub("[^0-9]", "", code_text), code))
    stop("Visible product ID does not match requested listing")
  # Only single-option pages are enabled. No guessed colour/default price.
  variants <- group$hasVariant
  if (length(variants) != 1L) stop("Multiple/unknown options; manual option verification required")
  variant <- variants[[1L]]
  if (!identical(as.character(variant$sku), product$momo_variant_sku) ||
      !identical(as.character(variant$name), product$momo_variant_label))
    stop("Variant SKU/label changed")
  offer <- variant$offers
  if (is.null(offer$priceCurrency) || offer$priceCurrency != "TWD")
    stop("Missing or unexpected currency")

  prices <- rvest::html_elements(doc, '[data-testid="price-main-container"]')
  if (length(prices) != 1L) stop("Missing/ambiguous main price block")
  block <- prices[[1L]]
  spans <- rvest::html_elements(block, ".font-price")
  price_rows <- lapply(spans, function(span) {
    parent <- xml2::xml_parent(span)
    label <- momo_text(rvest::html_element(parent, xpath = "./span[1]"))
    list(label = label, price = momo_money(momo_text(span)))
  })
  get_price <- function(labels) {
    matches <- Filter(function(x) !is.na(x$label) && x$label %in% labels, price_rows)
    if (length(matches) > 1L) stop("Ambiguous duplicate labelled prices")
    if (length(matches)) matches[[1L]]$price else NA_integer_
  }
  original <- get_price(c("市售價", "市價", "原價"))
  sale <- get_price(c("促銷價", "售價"))
  if (is.na(sale)) stop("No explicit ordinary selling price; JSON-LD may be conditional")
  extras <- Filter(function(x) !is.na(x$label) &&
    grepl("折後價|會員價|券後價|折價券價|限時價", x$label), price_rows)
  unknown <- Filter(function(x) is.na(x$label) ||
    !(x$label %in% c("市售價", "市價", "原價", "促銷價", "售價") ||
      grepl("折後價|會員價|券後價|折價券價|限時價", x$label)), price_rows)
  if (length(unknown)) stop("Unrecognised price label; review before collecting")
  extra <- NA_integer_
  extra_label <- NA_character_
  if (length(extras)) {
    amounts <- vapply(extras, function(x) x$price, integer(1))
    if (anyNA(amounts)) stop("Unparseable conditional price")
    best <- extras[[which.min(amounts)]]
    extra <- best$price
    extra_label <- momo_join(vapply(extras[amounts == extra], function(x) x$label, character(1)))
  }
  primary <- rvest::html_element(block, '[data-testid="price-primary-row"] .font-price')
  if (is.na(momo_text(primary)) || !identical(momo_money(momo_text(primary)), momo_money(as.character(offer$price))))
    stop("Displayed headline and selected variant schema price disagree")

  info <- rvest::html_element(doc, '[data-testid="goods-info"]')
  # Scope to the main purchase column, excluding global navigation/recommendations.
  purchase <- rvest::html_element(info, xpath = './ancestor::div[.//*[@data-testid="web-goods-price-container"]][1]')
  if (inherits(purchase, "xml_missing")) stop("Cannot isolate product purchase column")
  info_lines <- trimws(strsplit(momo_text(info), "\n", fixed = TRUE)[[1L]])
  promo <- info_lines[grepl("折|滿.*送|限時|特價|特惠|登記送|折扣", info_lines) & info_lines != "(說明)"]
  copy_nodes <- rvest::html_elements(purchase, "a, span, button")
  copy_text <- vapply(copy_nodes, momo_text, character(1))
  coupon <- copy_text[!is.na(copy_text) & grepl("折價券|優惠券|會員價|刷.*卡|回饋|券後", copy_text)]
  # Report explicit percent-off text only. Never derive a percent from amounts or 折.
  pct_text <- info_lines[grepl("[-−][0-9]+(?:\\.[0-9]+)?\\s*%|[0-9]+(?:\\.[0-9]+)?\\s*%\\s*off", info_lines, ignore.case = TRUE, perl = TRUE)]
  pct <- NA_real_
  if (length(pct_text) == 1L) {
    token <- regmatches(pct_text, regexpr("[0-9]+(?:\\.[0-9]+)?", pct_text, perl = TRUE))
    pct <- as.numeric(token)
  }
  purchase_text <- momo_text(purchase)
  marketplace <- grepl("第三方賣家|店家名稱|商店名稱|由.{1,40}銷售", purchase_text) ||
    any(grepl("/3p/|/3pGoods", rvest::html_attr(rvest::html_elements(purchase, "a[href]"), "href")))
  if (marketplace) stop("Possible marketplace seller; excluded from confirmed input")
  # Provisional normal-catalogue rule from spec 6.3, not legal seller verification.
  stock <- !grepl("已售完|已售罄|售完補貨|補貨中|商品目前無展售|尚未開賣", purchase_text)
  availability <- offer$availability
  if (!is.null(availability) && grepl("OutOfStock|SoldOut|Discontinued|PreOrder", availability))
    stock <- FALSE
  list(original_price = original, sale_price = sale, extra_price = extra,
    extra_price_label = extra_label, shown_discount_pct = pct,
    promo_tag = momo_join(promo), coupon_note = momo_join(coupon),
    seller_type = "platform", in_stock = stock)
}

momo_empty_row <- function(product, time, status = NA_integer_) {
  day <- format(time, "%Y-%m-%d", tz = "Asia/Taipei")
  data.frame(date = day, scraped_at = format(time, "%Y-%m-%d %H:%M:%S", tz = "Asia/Taipei"),
    platform = "momo", product_id = product$product_id, platform_item_id = product$momo_i_code,
    original_price = NA_integer_, sale_price = NA_integer_, extra_price = NA_integer_,
    extra_price_label = NA_character_, shown_discount_pct = NA_real_, promo_tag = NA_character_,
    coupon_note = NA_character_, seller_type = NA_character_, in_stock = NA,
    http_status = as.integer(status), source = "scraper", stringsAsFactors = FALSE)
}

momo_append <- function(row, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  exists <- file.exists(path) && file.info(path)$size > 0
  if (exists) {
    header <- names(read.csv(path, nrows = 0L, check.names = FALSE, fileEncoding = "UTF-8"))
    if (!identical(header, names(row))) stop("Existing CSV header differs: ", path)
  }
  con <- file(path, if (exists) "at" else "wt", encoding = "UTF-8")
  on.exit(close(con))
  write.table(row, con, sep = ",", row.names = FALSE, col.names = !exists,
    na = "NA", quote = TRUE, qmethod = "double", eol = "\n")
}

momo_save_raw <- function(body, code, time, run_id, raw_dir) {
  day <- format(time, "%Y-%m-%d", tz = "Asia/Taipei")
  run_path <- file.path(raw_dir, "momo", day, run_id, paste0(code, ".html.gz"))
  dir.create(dirname(run_path), recursive = TRUE, showWarnings = FALSE)
  con <- gzfile(run_path, "wb")
  tryCatch(writeBin(body, con), finally = close(con))
  canonical <- file.path(raw_dir, "momo", day, paste0(code, ".html.gz"))
  if (!file.exists(canonical) && !file.copy(run_path, canonical)) stop("Cannot save canonical raw capture")
  run_path
}

momo_read_products <- function(path) {
  products <- read.csv(path, colClasses = "character", check.names = FALSE,
    na.strings = c("", "NA"), fileEncoding = "UTF-8")
  required <- c("product_id", "brand", "model", "category", "momo_i_code",
    "momo_url", "momo_variant_sku", "momo_variant_label", "momo_expected_title")
  if (!all(required %in% names(products))) stop("Missing product/variant columns in ", path)
  products <- products[!is.na(products$momo_i_code), , drop = FALSE]
  if (!nrow(products)) stop("No confirmed momo products")
  if (anyDuplicated(products$product_id) || anyDuplicated(products$momo_i_code))
    stop("Duplicate product or momo listing IDs")
  for (key in required) if (anyNA(products[[key]]) || any(!nzchar(products[[key]])))
    stop("Missing required input: ", key)
  if (any(!grepl("^[0-9]+$", products$momo_i_code))) stop("momo IDs must be digits")
  expected <- paste0("https://www.momoshop.com.tw/product/", products$momo_i_code)
  if (any(products$momo_url != expected)) stop("Only the exact public canonical momo URL is supported")
  products
}

# One stateful, paced client per run. No retries or automatic redirects.
momo_client <- function(user_agent) {
  # Initial wait also keeps back-to-back invocations at least five seconds apart.
  last_request <- Sys.time()
  min_delay <- 5
  policy <- NULL
  function(url) {
    if (!grepl("^https://www[.]momoshop[.]com[.]tw/", url)) stop("Unexpected request host")
    path <- sub("^https://www[.]momoshop[.]com[.]tw", "", url)
    if (path != "/robots.txt" && (is.null(policy) || !policy$allowed(path)))
      return(list(status = NA_integer_, body = raw(), blocked = FALSE,
        error = "robots.txt disallows request or was not loaded", requested = FALSE))
    if (!is.na(last_request)) {
      elapsed <- as.numeric(difftime(Sys.time(), last_request, units = "secs"))
      if (elapsed < min_delay) Sys.sleep(min_delay - elapsed)
    }
    last_request <<- Sys.time()
    result <- tryCatch({
      response <- httr2::request(url) |>
        httr2::req_user_agent(user_agent) |>
        httr2::req_options(followlocation = FALSE) |>
        httr2::req_timeout(30) |>
        httr2::req_error(is_error = function(resp) FALSE) |>
        httr2::req_perform()
      headers <- as.list(unclass(httr2::resp_headers(response)))
      headers <- headers[intersect(names(headers), c("content-type", "date", "cache-control", "location"))]
      list(status = httr2::resp_status(response), body = httr2::resp_body_raw(response),
        blocked = FALSE, error = NULL, requested = TRUE,
        headers = headers)
    }, error = function(e) list(status = NA_integer_, body = raw(), blocked = FALSE,
      error = conditionMessage(e), requested = TRUE))
    result$time <- last_request
    result$blocked <- (!is.na(result$status) && result$status %in% c(403L, 429L)) ||
      momo_challenge(result$body)
    if (path == "/robots.txt" && identical(result$status, 200L) && !result$blocked) {
      policy <<- momo_robots(rawToChar(result$body))
      if (!isTRUE(policy$valid)) {
        policy <<- NULL
        result$error <- "robots.txt did not contain a valid user-agent group"
      } else min_delay <<- max(5, policy$delay)
    }
    result
  }
}

momo_run <- function(products, output_dir, raw_dir, log_dir, fetch,
                     now = function() Sys.time()) {
  run_time <- now()
  run_id <- paste0("run-", format(run_time, "%H%M%S", tz = "Asia/Taipei"), "-", Sys.getpid(),
    "-", sprintf("%06d", sample.int(999999L, 1L)))
  output <- file.path(output_dir, paste0("momo_", format(run_time, "%Y-%m-%d", tz = "Asia/Taipei"), ".csv"))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  lock <- file.path(output_dir, ".momo-lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("Another momo run is active, or a stale .momo-lock remains")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  # Refuse to fetch before discovering an incompatible existing output schema.
  if (file.exists(output) && file.info(output)$size > 0 &&
      !identical(names(read.csv(output, nrows = 0, check.names = FALSE, fileEncoding = "UTF-8")), momo_columns))
    stop("Existing output has an incompatible header")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_path <- file.path(log_dir, paste0("momo_", format(run_time, "%Y-%m-%d", tz = "Asia/Taipei"), ".jsonl"))
  log_event <- function(event) {
    event$run_id <- run_id
    line <- jsonlite::toJSON(event, auto_unbox = TRUE, na = "null", null = "null")
    cat(enc2utf8(line), "\n", file = log_path, append = TRUE, sep = "")
  }
  robots <- fetch("https://www.momoshop.com.tw/robots.txt")
  robots_path <- momo_save_raw(robots$body, "robots", run_time, run_id, raw_dir)
  stopped <- !identical(robots$status, 200L) || isTRUE(robots$blocked) || !is.null(robots$error)
  stop_reason <- if (stopped) "robots.txt unavailable, rate-limited or challenged; no product requests" else NULL
  log_event(list(event = "robots", http_status = robots$status, raw_file = robots_path,
    stopped = stopped, error = robots$error))
  success <- 0L
  attempted <- 0L
  failures <- 0L
  for (i in seq_len(nrow(products))) {
    product <- as.list(products[i, , drop = FALSE])
    time <- now()
    if (stopped) {
      response <- list(status = NA_integer_, body = raw(), requested = FALSE, error = stop_reason)
    } else {
      response <- fetch(product$momo_url)
      if (!is.null(response$time)) time <- response$time
    }
    row <- momo_empty_row(product, time, response$status)
    attempted <- attempted + as.integer(isTRUE(response$requested))
    raw_path <- NULL
    if (isTRUE(response$requested)) raw_path <- momo_save_raw(response$body, product$momo_i_code, time, run_id, raw_dir)
    error <- response$error
    if (isTRUE(response$blocked)) {
      stopped <- TRUE
      stop_reason <- paste0("Access blocked at ", product$product_id, "; remaining products not requested")
      error <- stop_reason
    } else if (!is.na(response$status) && response$status == 200L && !stopped) {
      parsed <- tryCatch(momo_parse(response$body, product), error = function(e) e)
      if (inherits(parsed, "error")) error <- conditionMessage(parsed)
      else for (key in names(parsed)) row[[key]] <- parsed[[key]]
    } else if (is.null(error)) error <- paste0("HTTP ", response$status, "; no price parsed")
    # On a midnight crossing, write the row to its true Taiwan request date.
    row_output <- file.path(output_dir, paste0("momo_", row$date, ".csv"))
    momo_append(row[, momo_columns], row_output)
    if (!is.na(row$sale_price)) success <- success + 1L else failures <- failures + 1L
    log_event(list(event = "product", product_id = product$product_id,
      platform_item_id = product$momo_i_code, scraped_at = row$scraped_at,
      http_status = row$http_status, raw_file = raw_path, requested = isTRUE(response$requested),
      error = error, headers = response$headers,
      seller_rule = if (!is.na(row$seller_type)) "spec 6.3 normal catalogue default; not independent legal proof" else NULL))
  }
  cat(sprintf("momo: products attempted=%d; products with a price=%d; rows=%d; output=%s\n",
    attempted, success, nrow(products), output))
  invisible(list(attempted = attempted, success = success, failures = failures,
    stopped = stopped, output = output, log = log_path, run_id = run_id))
}

