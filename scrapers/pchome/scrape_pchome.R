INPUT_COLUMNS <- c("product_id", "brand", "model", "category", "momo_url", "pchome_url",
                   "coupang_url", "biggo_url_momo", "biggo_url_pchome", "biggo_url_coupang")
OUTPUT_COLUMNS <- c("date", "scraped_at", "platform", "product_id", "platform_item_id",
                    "original_price", "sale_price", "extra_price", "extra_price_label",
                    "shown_discount_pct", "promo_tag", "coupon_note", "seller_type", "in_stock",
                    "http_status", "source", "fetch_status")
FETCH_STATUSES <- c("ok", "parse_failure", "http_error", "timeout", "blocked", "bad_input")
PACE_SECONDS <- 5               # NFR-1: gap between requests, retries included
RETRY_WAIT_SECONDS <- 60        # 8.2: wait before the one retry, and before each block workaround
MAX_RETRY_AFTER_SECONDS <- 300  # a longer Retry-After is capped so a run stays inside WF-7
MAX_BLOCKED_STREAK <- 3         # after this many products in a row end blocked, skip the long workarounds
# 8.2 / NFR-2: the identity used when the study user agent is blocked.
BROWSER_USER_AGENT <- paste("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                            "(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36")

tw_format <- function(time, pattern) format(time, pattern, tz = "Asia/Taipei")

read_products <- function(path) {
  if (!file.exists(path)) stop("Product table not found: ", path)
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  if (length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(239, 187, 191)))) {
    bytes <- bytes[-seq_len(3)]
  }
  text <- rawToChar(bytes)
  if (!validUTF8(text)) stop("Product table is not valid UTF-8")
  products <- withCallingHandlers(
    read.csv(path, encoding = "UTF-8", colClasses = "character",
             na.strings = character(), check.names = FALSE),
    warning = function(warning) stop("Invalid product table: ", conditionMessage(warning))
  )
  names(products) <- sub("^\ufeff", "", names(products), useBytes = TRUE)
  missing <- setdiff(INPUT_COLUMNS, names(products))
  if (length(missing)) stop("Missing input columns: ", paste(missing, collapse = ", "))
  if (anyDuplicated(names(products))) stop("Duplicate input column names")
  products
}

extract_item_id <- function(url) {
  pattern <- "^https?://24h\\.pchome\\.com\\.tw/prod/([A-Z0-9]{6}-[A-Z0-9]{9}(?:-[0-9]{3})?)/?(?:[?#].*)?$"
  matched <- regmatches(trimws(url), regexec(pattern, trimws(url), perl = TRUE,
                                           ignore.case = TRUE))[[1]]
  if (length(matched) != 2L) return(NA_character_)
  toupper(matched[2])
}

product_url <- function(item_id) paste0("https://24h.pchome.com.tw/prod/", item_id)

whole_price <- function(value) {
  if (length(value) != 1L || is.na(value) || is.list(value)) return(NA_integer_)
  value <- gsub("NT\\$|\\$|元|,|[[:space:]]", "", as.character(value))
  if (!grepl("^[0-9]+$", value)) return(NA_integer_)
  number <- suppressWarnings(as.numeric(value))
  if (!is.finite(number) || number > .Machine$integer.max) return(NA_integer_)
  as.integer(number)
}

clean_text <- function(text) trimws(gsub("(*UCP)\\s+", " ", text, perl = TRUE))

node_text <- function(node) clean_text(rvest::html_text2(node))

join_text <- function(text) {
  text <- unique(clean_text(text[!is.na(text)]))
  text <- text[nzchar(text)]
  if (length(text)) paste(text, collapse = " | ") else NA_character_
}

displayed_price <- function(nodes) {
  prices <- unique(vapply(nodes, function(node) whole_price(node_text(node)), integer(1)))
  if (length(prices) == 1L && !is.na(prices)) prices else NA_integer_
}

parse_product_page <- function(body, item_id) {
  failure <- function(note) list(fetch_status = "parse_failure", verification_note = note)
  document <- tryCatch(rvest::read_html(body, encoding = "UTF-8"), error = function(error) NULL)
  if (is.null(document)) return(failure("Response is not readable product HTML"))
  excluded <- rvest::html_elements(document, "script, style, template, noscript, [hidden], [aria-hidden='true']")
  xml2::xml_remove(excluded)
  styled <- rvest::html_elements(document, "[style]")
  hidden <- grepl("display\\s*:\\s*none|visibility\\s*:\\s*hidden",
                  rvest::html_attr(styled, "style"), ignore.case = TRUE)
  xml2::xml_remove(styled[hidden])
  roots <- rvest::html_elements(document, "[data-regression='prod_info']")
  if (length(roots) != 1L || !identical(rvest::html_attr(roots, "data-gtm-item_id"), item_id)) {
    return(failure("Product identity or selected variant cannot be verified in displayed markup"))
  }
  scope <- rvest::html_element(roots, ".c-boxGrid__item--prodBriefingArea")
  if (is.na(xml2::xml_name(scope)) || is.na(node_text(rvest::html_element(scope, "h1")))) {
    return(failure("Customer-facing product information is missing"))
  }
  price_blocks <- rvest::html_elements(scope, "[data-regression='prod_price']")
  if (length(price_blocks) != 1L) return(failure("Product price layout is missing or ambiguous"))
  price_block <- price_blocks[[1]]
  headline <- displayed_price(rvest::html_elements(price_block, ".c-prodPrice__price"))
  original_nodes <- rvest::html_elements(price_block,
    ".c-prodPrice__originalPrice, del, s, [style*='line-through']")
  overrides <- rvest::html_attr(original_nodes, "style")
  no_strike <- !is.na(overrides) & grepl("text-decoration[^;]*:\\s*none", overrides, ignore.case = TRUE)
  original <- displayed_price(original_nodes[!no_strike])
  labels <- rvest::html_elements(price_block, ".c-prodPrice__title")
  label_text <- node_text(labels)
  price_labels <- c(label_text, rvest::html_attr(rvest::html_elements(price_block, ".c-prodPrice"), "aria-label"))
  conditional <- any(grepl("折扣價|會員|折後|優惠價|首購|刷卡|券後", price_labels), na.rm = TRUE)
  sale <- headline
  extra <- NA_integer_
  extra_label <- NA_character_
  discounts <- rvest::html_elements(scope, "[data-regression='prod_discount'] .c-discountEvent__link")
  discount_text <- node_text(discounts)
  if (conditional) {
    baseline_nodes <- lapply(labels[label_text == "網路價"], xml2::xml_parent)
    baseline <- unlist(lapply(baseline_nodes, function(node) {
      rvest::html_elements(node, ".c-prodPrice__originalPrice, .c-prodPrice__price")
    }), recursive = FALSE)
    sale <- displayed_price(baseline)
    if (is.na(sale)) return(failure("Conditional headline has no verifiable unconditional selling price"))
    candidates <- rvest::html_elements(price_block, ".c-prodPrice__price")
    candidate_prices <- vapply(candidates, function(node) whole_price(node_text(node)), integer(1))
    matching_labels <- lapply(candidate_prices, function(price) {
      if (is.na(price)) return(character())
      discount_text[grepl(paste0("\\$", format(price, big.mark = "", scientific = FALSE), "([^0-9]|$)"),
                           gsub(",", "", discount_text, fixed = TRUE))]
    })
    verified <- which(!is.na(candidate_prices) & lengths(matching_labels) > 0L)
    if (length(verified)) {
      chosen <- verified[which.min(candidate_prices[verified])]
      extra <- candidate_prices[chosen]
      extra_label <- join_text(matching_labels[[chosen]])
    }
  } else if (length(label_text) && !all(label_text %in% c("網路價", "建議售價", "原價", "市價"))) {
    return(failure("Unrecognised price label; refusing to treat a conditional price as unconditional"))
  }
  stock_buttons <- rvest::html_elements(scope,
    "button[data-regression='product_button_addToCart'], button[data-regression='product_button_buyNow']")
  enabled <- is.na(rvest::html_attr(stock_buttons, "disabled")) &
    (is.na(rvest::html_attr(stock_buttons, "aria-disabled")) |
       rvest::html_attr(stock_buttons, "aria-disabled") != "true")
  sold_out <- grepl("已售完|暫時缺貨|售完補貨|已下架|到貨通知我", node_text(scope))
  # 7.1: an ok row is TRUE or FALSE. A shown price without a sold-out notice is for sale.
  in_stock <- if (any(enabled)) TRUE else if (sold_out) FALSE else !is.na(sale)
  if (is.na(sale) && in_stock) return(failure("No verified selling price or sold-out notice"))
  tag_nodes <- rvest::html_elements(scope, paste(
    ".o-prodMainName__colorPrimary300, [data-regression='prod_discount'] .c-label__text,",
    "[data-regression='prod_discount'] .c-discountEvent__link, .c-prodPriceTips .c-colorTag__text,",
    "[data-regression='prod_promoTag'] .c-label__text, [data-regression='prod_promoText'],",
    "[data-regression='prod_coupon'] .c-detailCol__title"))
  tag_text <- node_text(tag_nodes)
  badge_text <- node_text(rvest::html_elements(scope,
    "[data-regression='prod_discount'] .c-label__text, .c-prodPriceTips .c-colorTag__text"))
  badges <- badge_text[grepl("^-?[0-9]+(?:\\.[0-9]+)?%\\s*(?:off)?$", badge_text,
                           perl = TRUE, ignore.case = TRUE)]
  percentages <- unique(suppressWarnings(as.numeric(gsub("[^0-9.]", "", badges))))
  percentage <- if (length(percentages) == 1L) percentages else NA_real_
  coupon_nodes <- rvest::html_elements(scope,
    "[data-regression='prod_coupon'], [data-regression='prod_info_payment'] a")
  coupon_text <- node_text(coupon_nodes)
  notes <- c("Server-rendered product text only; image-only labels and client-loaded payment/coupon dialogs are unverified")
  if (conditional && is.na(extra)) notes <- c(notes, "Conditional price label could not be linked to displayed terms")
  list(fetch_status = "ok", sale_price = sale, original_price = original,
       extra_price = extra, extra_price_label = extra_label, shown_discount_pct = percentage,
       promo_tag = join_text(tag_text), coupon_note = join_text(c(discount_text, coupon_text)),
       # 7.3: 24h product pages are sold by PChome itself.
       seller_type = "platform", in_stock = in_stock,
       verification_note = paste(notes, collapse = "; "))
}

# 8.1: a page with the product block is never a challenge, so markers in its scripts (CAPTCHA
# widgets, Cloudflare's challenge-platform script) or a noscript notice cannot end a good row.
is_challenge <- function(body) {
  document <- tryCatch(rvest::read_html(body, encoding = "UTF-8"), error = function(error) NULL)
  if (!is.null(document) &&
      length(rvest::html_elements(document, "[data-regression='prod_info']"))) return(FALSE)
  text <- tryCatch(rawToChar(body), error = function(error) "")
  if (grepl("sec-if-cpt-container|cf-chl-|challenge-platform", text, perl = TRUE)) return(TRUE)
  if (is.null(document)) return(FALSE)
  xml2::xml_remove(rvest::html_elements(document, "script, style, template"))
  grepl("captcha|access denied|verify you are human|網頁載入中|javascript.{0,30}(required|check)",
        node_text(xml2::xml_root(document)), ignore.case = TRUE, perl = TRUE)
}

http_get <- function(url, user_agent) {
  request <- httr2::request(url)
  request <- httr2::req_user_agent(request, user_agent)
  request <- httr2::req_headers(request, `Accept-Language` = "zh-TW,zh;q=0.9")
  request <- httr2::req_timeout(request, 30)
  request <- httr2::req_options(request, followlocation = FALSE)
  request <- httr2::req_error(request, is_error = function(response) FALSE)
  response <- httr2::req_perform(request)
  list(status = httr2::resp_status(response), body = httr2::resp_body_raw(response),
       retry_after = httr2::resp_header(response, "retry-after"))
}

# 8.2 / NFR-5: the last workaround. Loads the page in a fresh headless Chrome (a new visitor)
# and returns the rendered HTML with the status of the page's own response.
browser_get <- function(url) {
  session <- chromote::ChromoteSession$new()
  on.exit(session$close(), add = TRUE)
  status <- NA_integer_
  session$Network$enable()
  session$Network$setUserAgentOverride(userAgent = BROWSER_USER_AGENT, acceptLanguage = "zh-TW,zh")
  session$Network$responseReceived(callback_ = function(event) {
    if (identical(event$type, "Document") && is.na(status)) status <<- as.integer(event$response$status)
  })
  loaded <- session$Page$loadEventFired(wait_ = FALSE, timeout_ = 30)
  session$Page$navigate(url, wait_ = FALSE)
  session$wait_for(loaded)
  html <- session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  if (is.na(status)) stop("Chrome received no response for ", url)
  list(status = status, body = charToRaw(enc2utf8(html)), retry_after = NULL)
}

save_body <- function(body, path) {
  if (file.exists(path)) stop("Refusing to overwrite raw response: ", path)
  connection <- gzfile(path, "wb")
  on.exit(close(connection))
  writeBin(body, connection)
}

new_row <- function(run_date, product_id, item_id) {
  data.frame(date = run_date, scraped_at = NA_character_, platform = "pchome",
             product_id = product_id, platform_item_id = item_id, original_price = NA_integer_,
             sale_price = NA_integer_, extra_price = NA_integer_, extra_price_label = NA_character_,
             shown_discount_pct = NA_real_, promo_tag = NA_character_, coupon_note = NA_character_,
             seller_type = NA_character_, in_stock = NA, http_status = NA_integer_,
             source = "scraper", fetch_status = "bad_input", stringsAsFactors = FALSE)
}

empty_rows <- function() new_row("", "", "")[0, ]

retry_delay <- function(header, now) {
  if (is.null(header) || length(header) != 1L || is.na(header)) return(RETRY_WAIT_SECONDS)
  seconds <- suppressWarnings(as.numeric(header))
  if (!is.finite(seconds)) {
    target <- suppressWarnings(as.POSIXct(header, format = "%a, %d %b %Y %H:%M:%S", tz = "GMT"))
    seconds <- as.numeric(difftime(target, now, units = "secs"))
  }
  if (!is.finite(seconds)) RETRY_WAIT_SECONDS
  else min(MAX_RETRY_AFTER_SECONDS, max(RETRY_WAIT_SECONDS, seconds))
}

# 8.1: what one response means for the row.
judge_response <- function(response, item_id) {
  if (is.null(response)) return(list(fetch_status = "timeout", http_status = NA_integer_, retry = TRUE))
  status <- as.integer(response$status)
  if (status == 403L || (status == 200L && is_challenge(response$body))) {
    return(list(fetch_status = "blocked", http_status = 403L, retry = FALSE))
  }
  if (status == 200L) {
    parsed <- tryCatch(parse_product_page(response$body, item_id), error = function(error) {
      list(fetch_status = "parse_failure", verification_note = conditionMessage(error))
    })
    return(list(fetch_status = parsed$fetch_status, http_status = status, retry = FALSE, parsed = parsed))
  }
  list(fetch_status = if (status == 429L) "blocked" else "http_error", http_status = status,
       retry = status == 429L || (status >= 500L && status < 600L))
}

# FR-5: the body the row was read from is <id>.html.gz; earlier attempts keep their number.
save_bodies <- function(bodies, raw_dir, raw_name) {
  for (index in seq_along(bodies)) {
    suffix <- if (index == length(bodies)) "" else paste0("__attempt", index)
    save_body(bodies[[index]], file.path(raw_dir, paste0(raw_name, suffix, ".html.gz")))
  }
}

# FR-8: platform, products, the count of each status that occurred, output file.
summary_line <- function(rows, output) {
  counts <- table(factor(rows$fetch_status, levels = FETCH_STATUSES))
  counts <- counts[counts > 0]
  parts <- if (length(counts)) paste(names(counts), counts, collapse = ", ") else "nothing to do"
  paste0("pchome: ", nrow(rows), " products | ", parts, " | ", output)
}

run_scraper <- function(args = character(), contact = Sys.getenv("SCRAPER_CONTACT"),
                        platform_dir = file.path("scrapers", "pchome"),
                        transport = http_get, clock = Sys.time, wait = Sys.sleep,
                        browser = if (requireNamespace("chromote", quietly = TRUE)) browser_get) {
  if (length(args) > 1L) stop("Usage: Rscript scrapers/pchome/scrape_pchome.R [products.csv]")
  if (!nzchar(trimws(contact)) || grepl("[\r\n]", contact)) stop("Set SCRAPER_CONTACT in .Renviron")
  input <- if (length(args)) args[1] else file.path("products", "products.csv")
  products <- read_products(input)
  duplicated_ids <- duplicated(products$product_id) | duplicated(products$product_id, fromLast = TRUE)
  included <- which(nzchar(trimws(products$pchome_url)))
  started <- clock()
  run_date <- tw_format(started, "%Y-%m-%d")
  stamp <- tw_format(started, "%Y-%m-%d_%H%M")
  output_dir <- file.path(platform_dir, "output")
  raw_parent <- file.path(platform_dir, "raw")
  raw_dir <- file.path(raw_parent, stamp)
  output <- file.path(output_dir, paste0("pchome_", stamp, ".csv"))
  if (file.exists(output) || dir.exists(raw_dir)) stop("Run already exists: ", stamp)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(raw_parent, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(output_dir) || !dir.exists(raw_parent)) stop("Cannot create output directories")
  if (!dir.create(raw_dir, showWarnings = FALSE)) stop("Cannot reserve run directory: ", raw_dir)
  # An interrupted run that saved nothing frees its minute again.
  on.exit(if (!length(list.files(raw_dir, all.files = TRUE, no.. = TRUE))) unlink(raw_dir, recursive = TRUE))
  user_agent <- paste0("PBA-Double11-study (NTHU ISS4066; contact: ", trimws(contact), ")")
  rows <- list()
  verification <- list()
  last_finished <- NULL
  blocked_streak <- 0L
  used_ids <- character()
  for (product_index in included) {
    product_id <- products$product_id[product_index]
    item_id <- extract_item_id(products$pchome_url[product_index])
    row <- new_row(run_date, product_id, item_id)
    verification_note <- "No customer-visible page verified"
    if (duplicated_ids[product_index] || !nzchar(trimws(product_id)) || is.na(item_id)) {
      message("pchome: bad_input at table row ", product_index + 1L, " (", product_id, ")")
    } else {
      raw_name <- if (item_id %in% used_ids) paste0(item_id, "__row", product_index) else item_id
      used_ids <- c(used_ids, item_id)
      url <- product_url(item_id)
      bodies <- list()
      attempt <- function(fetch) {
        if (!is.null(last_finished)) {
          elapsed <- as.numeric(difftime(clock(), last_finished, units = "secs"))
          if (elapsed < PACE_SECONDS) wait(PACE_SECONDS - elapsed)
        }
        row$scraped_at <<- tw_format(clock(), "%Y-%m-%d %H:%M:%S")
        response <- tryCatch(fetch(url), error = function(error) NULL)
        last_finished <<- clock()
        if (!is.null(response)) bodies[[length(bodies) + 1L]] <<- response$body
        c(judge_response(response, item_id), list(retry_after = response$retry_after))
      }
      plain <- function(url) transport(url, user_agent)
      persisting <- blocked_streak < MAX_BLOCKED_STREAK
      verdict <- attempt(plain)
      # 8.2: one retry. Once several products in a row ended blocked, a 429 is not waited on
      # again, so a site that refuses everything cannot push the run past WF-7.
      if (verdict$retry && (persisting || verdict$fetch_status != "blocked")) {
        wait(retry_delay(verdict$retry_after, clock()))
        verdict <- attempt(plain)
      }
      # 8.2: a block is worked around before the product counts as blocked: back off and come
      # back as a new visitor with a browser's identity, then in a fresh headless Chrome.
      if (verdict$fetch_status == "blocked" && persisting) {
        message("pchome: ", product_id, " blocked (HTTP ", verdict$http_status, "), retrying as a browser")
        wait(RETRY_WAIT_SECONDS)
        verdict <- attempt(function(url) transport(url, BROWSER_USER_AGENT))
        if (verdict$fetch_status == "blocked" && !is.null(browser)) {
          message("pchome: ", product_id, " still blocked, loading it in headless Chrome")
          wait(RETRY_WAIT_SECONDS)
          loaded <- attempt(browser)
          # Chrome failing to start or load says nothing about the site: the product stays blocked.
          if (loaded$fetch_status != "timeout") verdict <- loaded
        }
      }
      blocked_streak <- if (verdict$fetch_status == "blocked") blocked_streak + 1L else 0L
      save_bodies(bodies, raw_dir, raw_name)
      row$fetch_status <- verdict$fetch_status
      row$http_status <- verdict$http_status
      if (!is.null(verdict$parsed)) {
        for (field in intersect(names(verdict$parsed), OUTPUT_COLUMNS)) row[[field]] <- verdict$parsed[[field]]
        verification_note <- verdict$parsed$verification_note
      }
    }
    rows[[length(rows) + 1L]] <- row
    verification[[length(verification) + 1L]] <- data.frame(
      product_id = product_id, platform_item_id = item_id, fetch_status = row$fetch_status,
      price_source = if (row$fetch_status == "ok") "customer_visible_html" else NA_character_,
      coverage = if (row$fetch_status == "ok") "visible_text_only" else "unavailable",
      incomplete_fields = if (row$fetch_status == "ok")
        "extra_price | extra_price_label | shown_discount_pct | promo_tag | coupon_note" else NA_character_,
      verification_note = verification_note, stringsAsFactors = FALSE)
  }
  snapshot <- if (length(rows)) do.call(rbind, rows) else empty_rows()
  audit <- if (length(verification)) do.call(rbind, verification) else data.frame(
    product_id = character(), platform_item_id = character(), fetch_status = character(),
    price_source = character(), coverage = character(), incomplete_fields = character(),
    verification_note = character())
  write.csv(audit, file.path(raw_dir, "verification.csv"), row.names = FALSE,
            na = "NA", fileEncoding = "UTF-8")
  staged <- file.path(raw_dir, "snapshot.tmp")
  write.csv(snapshot, staged, row.names = FALSE, na = "NA", fileEncoding = "UTF-8")
  if (!file.copy(staged, output, overwrite = FALSE)) stop("Cannot publish new CSV: ", output)
  unlink(staged)
  cat(summary_line(snapshot, output), "\n", sep = "")
  if (any(snapshot$fetch_status == "ok")) {
    message("pchome: visible-text coverage only; client-loaded coupon/card/member offers and image-only labels are not fully verified. See ",
            file.path(raw_dir, "verification.csv"))
  }
  list(exit_code = if (any(snapshot$fetch_status == "ok")) 0L else 1L,
       data = snapshot, output = output, raw_dir = raw_dir)
}

main <- function() {
  needed <- c("httr2", "rvest", "xml2")
  missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Install required packages: ", paste(missing, collapse = ", "))
  run_scraper(commandArgs(trailingOnly = TRUE))$exit_code
}

if (sys.nframe() == 0L) {
  exit_code <- tryCatch(main(), error = function(error) {
    message("pchome: ", conditionMessage(error))
    1L
  })
  quit(save = "no", status = exit_code)
}
