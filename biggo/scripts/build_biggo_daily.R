# Builds data/biggo.csv from data/source/biggo_price_changes.csv.
#
# BigGo records only the moments a price changed. This turns those change points
# into one row per product x platform x day, holding the price in effect at
# 15:07 Taiwan time, the same daily slot our momo/PChome scrapers use.
#
# A day gets a row only when we can vouch for its price:
#   - there is a recorded change at or before 15:07 that day, and
#   - that day's 15:07 lies between the series' first and last recorded change, or inside
#     a reviewed tracking interval in biggo/records/history_coverage.csv
#     (BigGo kept tracking the listing, so an unchanged price can be carried on).
# A series that simply stops recording gets no rows after its last change.
#
# Coupang is excluded from the analysis (spec section 11), so only momo and
# PChome are built. brand, model and category are copied from products/products.csv so
# analysts need no join. The file is UTF-8 with a BOM (Excel shows the Chinese brand
# names) and LF line endings, the same as data/scrapes.csv. Run from the repository root:
#   Rscript biggo/scripts/build_biggo_daily.R

if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))

DAILY_SLOT <- "15:07:00"

read_text_csv <- function(path) {
  read.csv(path, colClasses = "character", na.strings = c("", "NA"),
           check.names = FALSE, fileEncoding = "UTF-8")
}

daily_series <- function(s, coverage, days) {
  s <- s[order(s$time), , drop = FALSE]
  prices_per_minute <- tapply(s$price, s$changed_at, function(p) length(unique(p)))
  if (any(prices_per_minute > 1)) {
    stop("Conflicting BigGo prices in the same minute for ", s$product_id[1], "/", s$platform[1])
  }
  slot <- as.POSIXct(paste(days, DAILY_SLOT), tz = "Asia/Taipei")
  last_change <- findInterval(as.numeric(slot), as.numeric(s$time))  # 0 = no change yet
  tracked <- slot >= min(s$time) & slot <= max(s$time)
  ranges <- coverage[coverage$product_id == s$product_id[1] & coverage$platform == s$platform[1], , drop = FALSE]
  for (i in seq_len(nrow(ranges))) {
    tracked <- tracked | (days >= as.Date(ranges$coverage_start[i]) & days <= as.Date(ranges$coverage_end[i]))
  }
  keep <- tracked & last_change > 0
  n <- sum(keep)
  data.frame(date = format(days[keep]), platform = rep(s$platform[1], n), product_id = rep(s$product_id[1], n),
             price = s$price[last_change[keep]], price_set_at = s$changed_at[last_change[keep]],
             stringsAsFactors = FALSE)
}

build_biggo_daily <- function(changes_path = "data/source/biggo_price_changes.csv",
                              coverage_path = "biggo/records/history_coverage.csv",
                              output_path = "data/biggo.csv",
                              first_day = as.Date("2025-09-01"),
                              last_day = as.Date("2025-11-25"),
                              platforms = c("momo", "pchome"),
                              products_path = "products/products.csv") {
  changes <- read_text_csv(changes_path)
  coverage <- read_text_csv(coverage_path)
  changes <- changes[changes$platform %in% platforms, , drop = FALSE]
  changes$time <- as.POSIXct(changes$changed_at, tz = "Asia/Taipei", format = "%Y-%m-%d %H:%M")
  changes$price <- suppressWarnings(as.numeric(changes$price))
  bad <- is.na(changes$time) | is.na(changes$price) | changes$price <= 0 | changes$price %% 1 != 0
  if (any(bad)) stop("Invalid BigGo timestamp or price in row(s): ", paste(head(which(bad) + 1, 5), collapse = ", "))
  changes$price <- as.integer(changes$price)
  if (anyNA(as.Date(coverage$coverage_start)) || anyNA(as.Date(coverage$coverage_end)) ||
      any(as.Date(coverage$coverage_start) > as.Date(coverage$coverage_end))) stop("Invalid coverage interval")

  days <- seq(first_day, last_day, by = "day")
  keys <- unique(changes[order(changes$product_id, changes$platform), c("product_id", "platform")])
  pieces <- lapply(seq_len(nrow(keys)), function(i) {
    s <- changes[changes$product_id == keys$product_id[i] & changes$platform == keys$platform[i], , drop = FALSE]
    daily_series(s, coverage, days)
  })
  daily <- do.call(rbind, pieces)

  products <- read_text_csv(products_path)[c("product_id", "brand", "model", "category")]
  unknown <- setdiff(daily$product_id, products$product_id)
  if (length(unknown)) stop("BigGo products missing from ", products_path, ": ", paste(head(unknown, 5), collapse = ", "))
  daily <- merge(daily, products, by = "product_id", sort = FALSE)
  daily <- daily[order(daily$product_id, daily$platform, daily$date),
                 c("date", "platform", "product_id", "brand", "model", "category", "price", "price_set_at")]
  rownames(daily) <- NULL

  # BOM + LF line endings on every OS, so a Windows rebuild matches the Linux one byte for byte.
  # Text columns are quoted only where a value needs it (a comma or a quote in a model name).
  con <- file(output_path, open = "wb")
  on.exit(close(con))
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  needs_quotes <- which(vapply(daily, function(x) is.character(x) && any(grepl("[,\"]", x)), logical(1)))
  write.csv(daily, con, row.names = FALSE, quote = if (length(needs_quotes)) unname(needs_quotes) else FALSE,
            fileEncoding = "UTF-8")
  invisible(daily)
}

if (sys.nframe() == 0L) {
  daily <- build_biggo_daily()
  cat(sprintf("Wrote data/biggo.csv: %d rows, %d listings, %s to %s\n", nrow(daily),
              nrow(unique(daily[c("product_id", "platform")])), min(daily$date), max(daily$date)))
}
