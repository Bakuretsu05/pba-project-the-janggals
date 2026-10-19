# Public momo page parsing and run helpers.
if (.Platform$OS.type == "windows" && !isTRUE(l10n_info()[["UTF-8"]]))
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
momo_columns <- c("date", "scraped_at", "platform", "product_id", "platform_item_id",
  "original_price", "sale_price", "extra_price", "extra_price_label",
  "shown_discount_pct", "promo_tag", "coupon_note", "seller_type", "in_stock",
  "http_status", "source", "fetch_status")

momo_text <- function(node) {
  if (length(node) == 0L || inherits(node, "xml_missing")) return(NA_character_)
  value <- trimws(gsub("\\s+", " ", rvest::html_text2(node), perl = TRUE))
  if (!nzchar(value)) NA_character_ else value
}
momo_join <- function(values, sep = " | ") {
  values <- trimws(gsub("\\s+", " ", values, perl = TRUE))
  values <- unique(values[!is.na(values) & nzchar(values)])
  if (length(values)) paste(values, collapse = sep) else NA_character_
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
  if (grepl('data-testid="price-main-container"', text, fixed = TRUE) &&
      grepl('data-testid="goods-code-info"', text, fixed = TRUE)) return(FALSE)
  grepl("Access Denied|Just a moment|sec-if-cpt-container|cf-chl-|challenge-platform|g-recaptcha|驗證您是人類|安全驗證",
    text, ignore.case = TRUE, perl = TRUE)
}

momo_product_group <- function(doc, code) {
  groups <- list()
  singles <- list()
  for (node in rvest::html_elements(doc, 'script[type="application/ld+json"]')) {
    parsed <- tryCatch(jsonlite::fromJSON(rvest::html_text(node), simplifyVector = FALSE),
      error = function(e) NULL)
    walk <- function(x) {
      if (!is.list(x)) return()
      if (identical(as.character(x$sku), code)) {
        if ("ProductGroup" %in% unlist(x[["@type"]])) groups[[length(groups) + 1L]] <<- x
        else if ("Product" %in% unlist(x[["@type"]])) singles[[length(singles) + 1L]] <<- x
      }
      for (child in x) if (is.list(child)) walk(child)
    }
    walk(parsed)
  }
  if (length(groups) == 1L) return(groups[[1L]])
  # Some single-option pages publish one Product with its own offer and no ProductGroup.
  if (!length(groups) && length(singles) == 1L) {
    group <- singles[[1L]]
    group$hasVariant <- list(singles[[1L]])
    return(group)
  }
  stop("Expected one ProductGroup or Product for requested item ID")
}

momo_parse <- function(body, product) {
  if (momo_challenge(body)) stop("Challenge page")
  doc <- xml2::read_html(body)
  code <- as.character(product$momo_i_code)
  group <- momo_product_group(doc, code)
  title <- group$name
  if (!is.null(product$momo_expected_title) && !is.na(product$momo_expected_title) &&
      !identical(title, product$momo_expected_title))
    stop("Product title changed; review exact model, formula, size and pack count")
  code_text <- momo_text(rvest::html_element(doc, '[data-testid="goods-code-info"]'))
  if (is.na(code_text) || !identical(gsub("[^0-9]", "", code_text), code))
    stop("Visible product ID does not match requested listing")
  variants <- group$hasVariant
  if (!length(variants)) stop("No options in the product schema")
  if (!is.null(product$momo_variant_sku) || !is.null(product$momo_variant_label)) {
    variants <- Filter(function(v)
      (is.null(product$momo_variant_sku) || identical(as.character(v$sku), product$momo_variant_sku)) &&
      (is.null(product$momo_variant_label) || identical(as.character(v$name), product$momo_variant_label)),
      variants)
    if (length(variants) != 1L) stop("Variant SKU/label changed")
  }
  # The product table names one option (colour, scent) but not which one on the page.
  # Several options are read only when they all have one price, so the choice cannot
  # matter; options with different prices are never guessed.
  offers <- lapply(variants, function(v) v$offers)
  currencies <- vapply(offers, function(o) as.character(o$priceCurrency %||% NA), character(1))
  if (anyNA(currencies) || any(currencies != "TWD")) stop("Missing or unexpected currency")
  amounts <- vapply(offers, function(o) momo_money(as.character(o$price %||% NA)), integer(1))
  if (anyNA(amounts) || length(unique(amounts)) != 1L)
    stop("Options have different prices; manual option verification required")
  offer <- offers[[1L]]

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
  info_lines <- trimws(strsplit(rvest::html_text2(info), "\n", fixed = TRUE)[[1L]])
  # Campaigns have their own block between the name and the description, one row each:
  # the dated campaign link (10/01~10/31 ★AirPods十在優惠) and its condition
  # (滿1件折1102元). The (說明) button beside a condition is not part of the label.
  promo_block <- rvest::html_elements(info, xpath = paste0("./div[not(.//*[@data-testid=",
    "'goods-name-content'] or .//*[@data-testid='goods-code-info'])]"))
  promo <- vapply(rvest::html_elements(promo_block, xpath = ".//div[not(div)]"), function(row) {
    parts <- xml2::xml_children(row)
    parts <- parts[xml2::xml_name(parts) != "button"]
    momo_join(vapply(parts, momo_text, character(1)), sep = " ")
  }, character(1))
  copy_nodes <- rvest::html_elements(purchase, "a, span, button")
  copy_text <- vapply(copy_nodes, momo_text, character(1))
  coupon <- copy_text[!is.na(copy_text) & grepl("折價券|優惠券|會員價|刷.*卡|回饋|券後", copy_text)]
  # Report explicit percent-off text only. Never derive a percent from amounts or 折.
  pct_text <- info_lines[grepl("[-−][0-9]+(?:\\.[0-9]+)?\\s*%|[0-9]+(?:\\.[0-9]+)?\\s*%\\s*off", info_lines, ignore.case = TRUE, perl = TRUE)]
  info_lines <- gsub("\\s+", " ", info_lines, perl = TRUE)
  pct <- NA_real_
  if (length(pct_text) == 1L) {
    token <- regmatches(pct_text, regexpr("[0-9]+(?:\\.[0-9]+)?\\s*%", pct_text, perl = TRUE))
    pct <- as.numeric(gsub("[^0-9.]", "", token))
  }
  purchase_text <- momo_text(purchase)
  marketplace <- grepl("第三方賣家|店家名稱|商店名稱|由.{1,40}銷售", purchase_text) ||
    any(grepl("/3p/|/3pGoods", rvest::html_attr(rvest::html_elements(purchase, "a[href]"), "href")))
  # Provisional normal-catalogue rule from spec 7.3, not legal seller verification.
  stock <- !grepl("已售完|已售罄|售完補貨|補貨中|商品目前無展售|尚未開賣", purchase_text)
  # With several options the row's own option is unknown, so mixed stock is NA.
  out <- grepl("OutOfStock|SoldOut|Discontinued|PreOrder",
    vapply(offers, function(o) as.character(o$availability %||% ""), character(1)))
  if (all(out)) stock <- FALSE else if (any(out)) stock <- NA
  list(original_price = original, sale_price = sale, extra_price = extra,
    extra_price_label = extra_label, shown_discount_pct = pct,
    promo_tag = momo_join(promo), coupon_note = momo_join(coupon),
    seller_type = if (marketplace) "marketplace" else "platform", in_stock = stock)
}


momo_input_columns <- c("product_id", "brand", "model", "category", "momo_url",
  "pchome_url", "coupang_url", "biggo_url_momo", "biggo_url_pchome", "biggo_url_coupang")

momo_extract_id <- function(url) {
  parsed <- tryCatch(httr2::url_parse(trimws(url)), error = function(e) NULL)
  if (is.null(parsed) || !tolower(parsed$scheme) %in% c("http", "https") ||
      !tolower(parsed$hostname) %in% c("www.momoshop.com.tw", "momoshop.com.tw", "m.momoshop.com.tw"))
    return(NA_character_)
  query_ids <- unlist(parsed$query[names(parsed$query) == "i_code"], use.names = FALSE)
  path_id <- if (grepl("^/product/[0-9]+/?$", parsed$path))
    sub("^/product/([0-9]+)/?$", "\\1", parsed$path) else character()
  ids <- unique(c(query_ids, path_id))
  if (length(ids) != 1L || !grepl("^[0-9]+$", ids)) NA_character_ else ids[[1L]]
}

momo_read_products <- function(path) {
  if (!file.exists(path)) stop("Product table is missing: ", path)
  products <- read.csv(path, colClasses = "character", check.names = FALSE,
    na.strings = c("", "NA"), fileEncoding = "UTF-8")
  if (!all(momo_input_columns %in% names(products))) stop("Product table is missing required columns")
  duplicate <- duplicated(products$product_id) | duplicated(products$product_id, fromLast = TRUE)
  products$momo_i_code <- vapply(products$momo_url, function(url)
    if (is.na(url) || !nzchar(trimws(url))) NA_character_ else momo_extract_id(url), character(1))
  products$momo_bad_input <- duplicate | is.na(products$product_id) | !nzchar(trimws(products$product_id)) |
    is.na(products$momo_i_code)
  products <- products[!is.na(products$momo_url) & nzchar(trimws(products$momo_url)), , drop = FALSE]
  products$momo_url <- ifelse(is.na(products$momo_i_code), NA_character_,
    paste0("https://www.momoshop.com.tw/product/", products$momo_i_code))
  products
}

momo_new_row <- function(product, date) {
  data.frame(date = date, scraped_at = NA_character_, platform = "momo",
    product_id = product$product_id, platform_item_id = product$momo_i_code,
    original_price = NA_integer_, sale_price = NA_integer_, extra_price = NA_integer_,
    extra_price_label = NA_character_, shown_discount_pct = NA_real_, promo_tag = NA_character_,
    coupon_note = NA_character_, seller_type = NA_character_, in_stock = NA,
    http_status = NA_integer_, source = "scraper", fetch_status = "bad_input",
    stringsAsFactors = FALSE)
}

momo_is_sold_out <- function(body) {
  text <- tryCatch({
    doc <- xml2::read_html(body)
    xml2::xml_remove(rvest::html_elements(doc, "script,style,noscript,template"))
    main <- rvest::html_element(doc, "main")
    if (inherits(main, "xml_missing")) main <- rvest::html_element(doc, "body")
    momo_text(main)
  }, error = function(e) NA_character_)
  !is.na(text) && !grepl("網頁不存在|網頁無法顯示|找不到商品", text) &&
    grepl("商品目前無展售|商品已下架|已售完|已售罄|售完補貨|補貨中", text)
}

# One client per run; errors are returned as data so later products still run.
momo_http_client <- function(contact, sleep = Sys.sleep, clock = Sys.time) {
  previous <- clock()
  function(url, browser_agent = FALSE) {
    elapsed <- as.numeric(difftime(clock(), previous, units = "secs"))
    if (elapsed < 5) sleep(5 - elapsed)
    previous <<- clock()
    ua <- paste0("PBA-Double11-study (NTHU ISS4066; contact: ", contact, ")")
    if (browser_agent) ua <- paste0("Mozilla/5.0 (compatible; ", ua, ")")
    result <- tryCatch({
      response <- httr2::request(url) |>
        httr2::req_user_agent(ua) |>
        httr2::req_options(followlocation = FALSE) |>
        httr2::req_timeout(30) |>
        httr2::req_error(is_error = function(resp) FALSE) |>
        httr2::req_perform()
      list(status = httr2::resp_status(response), body = httr2::resp_body_raw(response),
        error = NULL, received = TRUE)
    }, error = function(e) list(status = NA_integer_, body = raw(),
      error = conditionMessage(e), received = FALSE))
    result$sent_at <- previous
    result
  }
}

momo_archive <- function(response, dir, code, suffix = "") {
  if (!isTRUE(response$received)) return(NULL)
  path <- file.path(dir, paste0(code, suffix, ".html.gz"))
  con <- gzfile(path, "wb")
  tryCatch(writeBin(response$body, con), finally = close(con))
  path
}

momo_collect <- function(products, platform_dir, contact, fetch = NULL,
                         run_started = Sys.time(), sleep = Sys.sleep) {
  if (!nzchar(contact) || grepl("[\r\n]", contact)) stop("SCRAPER_CONTACT must be set")
  if (is.null(fetch)) fetch <- momo_http_client(contact, sleep = sleep)
  date <- format(run_started, "%Y-%m-%d", tz = "Asia/Taipei")
  stamp <- paste0(date, "_", format(run_started, "%H%M", tz = "Asia/Taipei"))
  output_dir <- file.path(platform_dir, "output")
  output <- file.path(output_dir, paste0("momo_", stamp, ".csv"))
  raw_dir <- file.path(platform_dir, "raw", stamp)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(output)) stop("Run file already exists; no requests sent: ", output)
  lock <- paste0(output, ".lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("This run is already active: ", stamp)
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  rows <- list()
  audit <- list()
  for (i in seq_len(nrow(products))) {
    product <- as.list(products[i, , drop = FALSE])
    row <- momo_new_row(product, date)
    error <- NULL
    attempts <- list()
    if (!isTRUE(product$momo_bad_input)) {
      response <- fetch(product$momo_url)
      attempts[[1L]] <- response
      row$scraped_at <- format(response$sent_at, "%Y-%m-%d %H:%M:%S", tz = "Asia/Taipei")
      retryable <- is.na(response$status) || response$status == 429L || response$status >= 500L
      if (retryable) {
        sleep(60)
        response <- fetch(product$momo_url)
        attempts[[length(attempts) + 1L]] <- response
      }
      blocked <- function(r) (!is.na(r$status) && r$status %in% c(403L, 429L)) ||
        momo_challenge(r$body)
      # One bounded alternate, still study-identified user agent; no proxies or login.
      if (blocked(response)) {
        sleep(5)
        response <- fetch(product$momo_url, browser_agent = TRUE)
        attempts[[length(attempts) + 1L]] <- response
      }
      code <- product$momo_i_code
      # Duplicate source IDs under different product IDs must not overwrite a response.
      if (any(vapply(rows, function(r) identical(r$platform_item_id, code), logical(1))))
        code <- paste0(code, "__row", i)
      for (j in seq_along(attempts)) {
        suffix <- if (j == length(attempts)) "" else paste0("__attempt", j)
        momo_archive(attempts[[j]], raw_dir, code, suffix)
      }
      row$http_status <- response$status
      error <- response$error
      if (blocked(response)) {
        row$fetch_status <- "blocked"
        if (momo_challenge(response$body)) row$http_status <- 403L
      } else if (is.na(response$status)) {
        row$fetch_status <- "timeout"
      } else if (response$status != 200L) {
        row$fetch_status <- "http_error"
      } else {
        parsed <- tryCatch(momo_parse(response$body, product), error = function(e) e)
        if (!inherits(parsed, "error")) {
          for (name in names(parsed)) row[[name]] <- parsed[[name]]
          row$fetch_status <- "ok"
        } else if (momo_is_sold_out(response$body)) {
          row$in_stock <- FALSE
          row$fetch_status <- "ok"
          error <- conditionMessage(parsed)
        } else {
          row$fetch_status <- "parse_failure"
          error <- conditionMessage(parsed)
        }
      }
    } else error <- "Duplicate/missing product_id or no valid momo listing ID in URL"
    rows[[i]] <- row
    audit[[i]] <- list(product_id = product$product_id, fetch_status = row$fetch_status,
      error = error, attempts = length(attempts),
      note = "ok verifies supported visible price layout; hidden/image-only offers and multi-option pages have incomplete coverage")
  }
  result <- if (length(rows)) do.call(rbind, rows) else {
    p <- list(product_id = NA_character_, momo_i_code = NA_character_)
    momo_new_row(p, date)[FALSE, ]
  }
  result <- result[, momo_columns, drop = FALSE]
  write.csv(result, output, row.names = FALSE, na = "NA", fileEncoding = "UTF-8")
  writeLines(jsonlite::toJSON(audit, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"),
    file.path(raw_dir, "verification.json"), useBytes = TRUE)
  counts <- table(factor(result$fetch_status,
    levels = c("ok", "parse_failure", "http_error", "timeout", "blocked", "bad_input")))
  summary <- paste(paste(names(counts), as.integer(counts)), collapse = ", ")
  cat(sprintf("momo: %d products | %s | %s\n", nrow(products), summary, output))
  invisible(list(rows = result, output = output, raw_dir = raw_dir,
    exit_status = if (any(result$fetch_status == "ok")) 0L else 1L))
}
