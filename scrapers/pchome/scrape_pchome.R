INPUT_COLUMNS <- c("product_id", "brand", "model", "category", "momo_url", "pchome_url",
                   "coupang_url", "biggo_url_momo", "biggo_url_pchome", "biggo_url_coupang")
OUTPUT_COLUMNS <- c("date", "scraped_at", "platform", "product_id", "platform_item_id",
                    "original_price", "sale_price", "extra_price", "extra_price_label",
                    "shown_discount_pct", "promo_tag", "coupon_note", "seller_type", "in_stock",
                    "http_status", "source", "fetch_status")
FETCH_STATUSES <- c("ok", "parse_failure", "http_error", "timeout", "blocked", "bad_input")

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
  in_stock <- if (any(enabled)) TRUE else if (sold_out) FALSE else NA
  if (is.na(sale) && !identical(in_stock, FALSE)) return(failure("No verified selling price or sold-out notice"))
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
       seller_type = if (isTRUE(grepl("PChome 倉庫出貨", node_text(rvest::html_element(scope,
         "[data-regression='prod_info_ship']")), fixed = TRUE))) "platform" else NA_character_,
       in_stock = in_stock, verification_note = paste(notes, collapse = "; "))
}

is_challenge <- function(body) {
  text <- tryCatch(rawToChar(body), error = function(error) "")
  grepl("captcha|access denied|sec-if-cpt-container|cf-chl-|challenge-platform|verify you are human|網頁載入中|javascript.{0,30}(required|check)",
        text, ignore.case = TRUE, perl = TRUE)
}

http_get <- function(url, user_agent) {
  request <- httr2::request(url)
  request <- httr2::req_user_agent(request, user_agent)
  request <- httr2::req_timeout(request, 30)
  request <- httr2::req_options(request, followlocation = FALSE)
  request <- httr2::req_error(request, is_error = function(response) FALSE)
  response <- httr2::req_perform(request)
  list(status = httr2::resp_status(response), body = httr2::resp_body_raw(response),
       retry_after = httr2::resp_header(response, "retry-after"))
}

save_body <- function(body, path) {
  if (file.exists(path)) stop("Refusing to overwrite raw response: ", path)
  connection <- gzfile(path, "wb")
  on.exit(close(connection))
  writeBin(body, connection)
}

empty_rows <- function() {
  data.frame(date = character(), scraped_at = character(), platform = character(),
             product_id = character(), platform_item_id = character(), original_price = integer(),
             sale_price = integer(), extra_price = integer(), extra_price_label = character(),
             shown_discount_pct = numeric(), promo_tag = character(), coupon_note = character(),
             seller_type = character(), in_stock = logical(), http_status = integer(),
             source = character(), fetch_status = character(), stringsAsFactors = FALSE)
}

new_row <- function(run_date, product_id, item_id) {
  data.frame(date = run_date, scraped_at = NA_character_, platform = "pchome",
             product_id = product_id, platform_item_id = item_id, original_price = NA_integer_,
             sale_price = NA_integer_, extra_price = NA_integer_, extra_price_label = NA_character_,
             shown_discount_pct = NA_real_, promo_tag = NA_character_, coupon_note = NA_character_,
             seller_type = NA_character_, in_stock = NA, http_status = NA_integer_,
             source = "scraper", fetch_status = "bad_input", stringsAsFactors = FALSE)
}

retry_delay <- function(header, now) {
  if (is.null(header) || length(header) != 1L || is.na(header)) return(60)
  seconds <- suppressWarnings(as.numeric(header))
  if (!is.finite(seconds)) {
    target <- suppressWarnings(as.POSIXct(header, format = "%a, %d %b %Y %H:%M:%S", tz = "GMT"))
    seconds <- as.numeric(difftime(target, now, units = "secs"))
  }
  if (!is.finite(seconds)) 60 else max(60, seconds)
}

run_scraper <- function(args = character(), contact = Sys.getenv("SCRAPER_CONTACT"),
                        platform_dir = file.path("scrapers", "pchome"),
                        transport = http_get, clock = Sys.time, wait = Sys.sleep) {
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
  user_agent <- paste0("PBA-Double11-study (NTHU ISS4066; contact: ", trimws(contact), ")")
  rows <- list()
  verification <- list()
  last_finished <- NULL
  site_blocked <- FALSE
  used_ids <- character()
  for (product_index in included) {
    product_id <- products$product_id[product_index]
    item_id <- extract_item_id(products$pchome_url[product_index])
    row <- new_row(run_date, product_id, item_id)
    verification_note <- "No customer-visible page verified"
    if (duplicated_ids[product_index] || !nzchar(trimws(product_id)) || is.na(item_id)) {
      message("pchome: bad_input at table row ", product_index + 1L, " (", product_id, ")")
    } else if (site_blocked) {
      row$fetch_status <- "blocked"
    } else {
      raw_name <- if (item_id %in% used_ids) paste0(item_id, "__row", product_index) else item_id
      used_ids <- c(used_ids, item_id)
      for (attempt in 1:2) {
        if (!is.null(last_finished)) {
          elapsed <- as.numeric(difftime(clock(), last_finished, units = "secs"))
          if (elapsed < 5) wait(5 - elapsed)
        }
        row$scraped_at <- tw_format(clock(), "%Y-%m-%d %H:%M:%S")
        response <- tryCatch(transport(product_url(item_id), user_agent), error = function(error) NULL)
        last_finished <- clock()
        row$http_status <- if (is.null(response)) NA_integer_ else as.integer(response$status)
        if (!is.null(response)) {
          suffix <- if (attempt == 1L) "" else paste0("__attempt", attempt)
          save_body(response$body, file.path(raw_dir, paste0(raw_name, suffix, ".html.gz")))
        }
        if (is.null(response)) {
          row$fetch_status <- "timeout"
        } else if (row$http_status == 403L ||
                   (row$http_status == 200L && is_challenge(response$body))) {
          row$fetch_status <- "blocked"
          if (row$http_status == 200L) row$http_status <- 403L
          site_blocked <- TRUE
          message("pchome: access restriction received; stopping further site requests")
          break
        } else if (row$http_status == 200L) {
          parsed <- tryCatch(parse_product_page(response$body, item_id), error = function(error) {
            list(fetch_status = "parse_failure", verification_note = conditionMessage(error))
          })
          for (field in intersect(names(parsed), OUTPUT_COLUMNS)) row[[field]] <- parsed[[field]]
          verification_note <- parsed$verification_note
          break
        } else {
          row$fetch_status <- if (row$http_status == 429L) "blocked" else "http_error"
        }
        retryable <- is.null(response) || row$http_status == 429L ||
          (row$http_status >= 500L && row$http_status < 600L)
        if (attempt == 1L && retryable) {
          header <- if (is.null(response)) NULL else response$retry_after
          wait(retry_delay(header, clock()))
        } else {
          if (row$fetch_status == "blocked") site_blocked <- TRUE
          break
        }
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
  counts <- table(factor(snapshot$fetch_status, levels = FETCH_STATUSES))
  summary <- paste(paste(names(counts), as.integer(counts)), collapse = ", ")
  cat("pchome: ", nrow(snapshot), " products | ", summary, " | ", output, "\n", sep = "")
  if (any(snapshot$fetch_status == "ok")) {
    message("pchome: visible-text coverage only; client-loaded coupon/card/member offers and image-only labels are not fully verified. See ",
            file.path(raw_dir, "verification.csv"))
  }
  list(exit_code = if (any(snapshot$fetch_status == "ok")) 0L else 1L,
       data = snapshot, output = output, raw_dir = raw_dir)
}

main <- function() {
  needed <- c("httr2", "rvest", "jsonlite")
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
