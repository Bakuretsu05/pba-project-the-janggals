# Base R only. Snapshot facts and BigGo history stay separate until this build.
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
read_table <- function(path, required) {
  x <- read.csv(path, colClasses = "character", check.names = FALSE,
                na.strings = c("", "NA"), fileEncoding = "UTF-8")
  if (!all(required %in% names(x))) stop("Missing columns in ", path)
  x
}
positive <- function(x) {
  n <- suppressWarnings(as.numeric(x))
  ifelse(is.finite(n) & n > 0, n, NA_real_)
}
tw_time <- function(x) as.POSIXct(x, tz = "Asia/Taipei")
fmt_day <- function(x) format(x, "%Y-%m-%d", tz = "Asia/Taipei")
discount <- function(reference, price) {
  if (is.na(reference) || is.na(price) || reference <= 0) NA_real_ else
    (reference - price) / reference
}

# A time-limited reduction counts as unconditional under the proposal. Unknown,
# membership/card/coupon labels are never silently treated as unconditional.
payable_price <- function(row) {
  if (!nrow(row) || is.na(row$fetch_status[1]) || row$fetch_status[1] != "ok") return(NA_real_)
  sale <- positive(row$sale_price[1])
  extra <- positive(row$extra_price[1])
  label <- row$extra_price_label[1]
  if (!is.na(extra) && !is.na(label) && grepl("\u9650\u6642", label) &&
      !grepl("\u6703\u54e1|\u5238|\u5361|\u9ede|\u6eff|member|coupon|card", label, ignore.case = TRUE)) {
    if (is.na(sale)) extra else min(sale, extra)
  } else sale
}

daily_history <- function(changes, coverage, product_id, platform, year, as_of) {
  first <- as.Date(sprintf("%d-09-01", year))
  last <- min(as.Date(sprintf("%d-11-25", year)), as_of)
  if (last < first) return(data.frame(date = as.Date(character()), price = numeric()))
  dates <- seq(first, last, by = "day")
  result <- data.frame(date = dates, price = NA_real_)
  if (!nrow(changes)) return(result)
  changes$time <- tw_time(changes$changed_at)
  changes$value <- positive(changes$price)
  if (anyNA(changes$time) || anyNA(changes$value)) stop("Invalid BigGo timestamp/price: ", product_id)
  changes <- changes[order(changes$time), ]
  for (timestamp in unique(changes$changed_at)) {
    if (length(unique(changes$value[changes$changed_at == timestamp])) > 1)
      stop("Conflicting BigGo prices at ", timestamp, " for ", product_id, "/", platform)
  }
  # A change-point table alone does not establish when tracking stopped. Carry
  # forward only between observed points, or inside an explicitly reviewed range.
  ranges <- coverage[coverage$product_id == product_id & coverage$platform == platform, , drop = FALSE]
  bounds <- if (nrow(ranges)) data.frame(start = as.Date(ranges$coverage_start),
                                       end = as.Date(ranges$coverage_end)) else NULL
  if (!is.null(bounds) && (anyNA(bounds) || any(bounds$start > bounds$end))) stop("Invalid coverage interval")
  query <- tw_time(paste(dates, "15:07:00"))
  for (i in seq_along(dates)) {
    known <- query[i] >= min(changes$time) && query[i] <= max(changes$time)
    if (!is.null(bounds)) known <- known || any(dates[i] >= bounds$start & dates[i] <= bounds$end)
    before <- which(changes$time <= query[i])
    if (known && length(before)) result$price[i] <- tail(changes$value[before], 1)
  }
  result
}

complete_prices <- function(daily, dates) {
  prices <- daily$price[match(dates, daily$date)]
  if (!length(prices) || anyNA(prices)) NULL else prices
}

build_analysis <- function(snapshots_path = "output/combined/combined_snapshots.csv",
                           output_dir = "output/analysis", as_of = Sys.Date(),
                           products_path = "products/products.csv",
                           history_path = "biggo/price_changes.csv",
                           config_dir = "analysis/config") {
  products <- read_table(products_path, c("product_id", "brand", "model", "category"))
  if (anyDuplicated(products$product_id)) stop("Duplicate product IDs in product table")
  snapshots <- read_table(snapshots_path, c("product_id", "platform", "date", "scraped_at",
      "original_price", "sale_price", "extra_price", "extra_price_label", "fetch_status", "source_run_id"))
  history <- read_table(history_path, c("product_id", "platform", "changed_at", "price"))
  if (nrow(history) && (anyNA(history$product_id) || anyNA(history$platform) ||
      any(!history$platform %in% c("momo", "pchome", "coupang")))) stop("Invalid BigGo identity")
  coverage <- read_table(file.path(config_dir, "history_coverage.csv"),
                         c("product_id", "platform", "coverage_start", "coverage_end", "note"))
  decisions <- read_table(file.path(config_dir, "event_decisions.csv"),
      c("product_id", "platform", "year", "price_start_date", "snapshot_run_id", "campaigns_reviewed", "note"))
  campaigns <- read_table(file.path(config_dir, "campaign_periods.csv"), c("platform", "start_date", "end_date", "note"))
  decision_key <- paste(decisions$product_id, decisions$platform, decisions$year)
  if (anyDuplicated(decision_key)) stop("Duplicate event decisions")
  if (nrow(decisions) && (anyNA(decisions$product_id) || anyNA(decisions$platform) ||
      any(!decisions$product_id %in% products$product_id) ||
      any(!decisions$platform %in% c("momo", "pchome")) || any(!decisions$year %in% c("2025", "2026"))))
    stop("Invalid event decision identity")
  if (nrow(campaigns)) {
    campaign_start <- as.Date(campaigns$start_date)
    campaign_end <- as.Date(campaigns$end_date)
    if (anyNA(campaign_start) || anyNA(campaign_end) || any(campaign_start > campaign_end) ||
        anyNA(campaigns$platform) || any(!campaigns$platform %in% c("all", "momo", "pchome")))
      stop("Invalid campaign period")
  }
  as_of <- as.Date(as_of)
  if (is.na(as_of)) stop("Invalid as-of date")
  records <- list()
  for (pid in products$product_id) for (platform in c("momo", "pchome")) for (year in c(2025L, 2026L)) {
    metadata <- products[products$product_id == pid, ]
    event_day <- as.Date(sprintf("%d-11-11", year))
    october <- seq(as.Date(sprintf("%d-10-01", year)), as.Date(sprintf("%d-10-31", year)), by = "day")
    november <- seq(as.Date(sprintf("%d-11-01", year)), as.Date(sprintf("%d-11-10", year)), by = "day")
    h <- history[history$product_id == pid & history$platform == platform, , drop = FALSE]
    daily <- daily_history(h, coverage, pid, platform, year, as_of)
    decision <- decisions[decision_key == paste(pid, platform, year), , drop = FALSE]
    start <- as.Date(NA_character_)
    campaigns_reviewed <- nrow(decision) == 1 && !is.na(decision$campaigns_reviewed) &&
      toupper(decision$campaigns_reviewed) == "TRUE"
    if (nrow(decision) && !is.na(decision$price_start_date)) {
      start <- as.Date(decision$price_start_date)
      if (is.na(start) || start < as.Date(sprintf("%d-10-01", year)) || start > event_day)
        stop("price_start_date must be between Oct 1 and Nov 11 of its year")
    }
    flags <- character()
    if (as_of < event_day) flags <- c(flags, "event_not_observed_yet")
    listed <- original <- NA_real_
    selected_run <- selected_time <- NA_character_
    if (year == 2026L && as_of >= event_day) {
      # Default is the earliest actual Nov 11 production collection per platform.
      # Select the run before selecting this product: failed rows are not replaced
      # with a later, cheaper successful observation.
      eligible <- snapshots[snapshots$platform == platform & snapshots$date == as.character(event_day), , drop = FALSE]
      if (nrow(decision) && !is.na(decision$snapshot_run_id)) {
        selected_run <- decision$snapshot_run_id
        eligible <- eligible[eligible$source_run_id == selected_run, , drop = FALSE]
      } else if (nrow(eligible)) {
        time <- if ("run_started_at" %in% names(eligible)) eligible$run_started_at else eligible$scraped_at
        selected_run <- eligible$source_run_id[order(time, as.numeric(eligible$source_run_id), na.last = TRUE)[1]]
        eligible <- eligible[eligible$source_run_id == selected_run, , drop = FALSE]
      }
      row <- eligible[eligible$product_id == pid, , drop = FALSE]
      if (nrow(row) > 1) stop("Duplicate product in selected snapshot")
      if (nrow(row)) {
        listed <- payable_price(row)
        if (row$fetch_status == "ok") original <- positive(row$original_price[1])
        selected_time <- row$scraped_at[1]
        if (row$fetch_status != "ok") flags <- c(flags, "selected_snapshot_failed")
      } else flags <- c(flags, "missing_event_snapshot")
    } else if (year == 2025L && as_of >= event_day) {
      listed <- daily$price[match(event_day, daily$date)]
      if (!length(listed)) listed <- NA_real_
    }
    if (is.na(listed)) flags <- c(flags, "missing_listed_price")
    if (year == 2026L && is.na(original)) flags <- c(flags, "no_advertised_reference")
    if (!nrow(h)) flags <- c(flags, "missing_biggo_history")
    if (is.na(start)) flags <- c(flags, "price_start_date_needs_review")
    # A candidate is evidence for review, never silently accepted as the event onset.
    candidate <- as.Date(NA_character_)
    if (!is.na(listed) && nrow(h)) {
      t <- tw_time(h$changed_at)
      past <- which(t <= tw_time(paste(event_day, "15:07:00")))
      if (length(past)) {
        ordered <- past[order(t[past])]
        values <- positive(h$price[ordered])
        if (!anyNA(values) && tail(values, 1) == listed) {
          different <- which(values != listed)
          first_same <- if (length(different)) tail(different, 1) + 1L else 1L
          candidate <- as.Date(fmt_day(t[ordered[first_same]]))
        }
      }
    }
    october_prices <- complete_prices(daily, october)
    november_prices <- complete_prices(daily, november)
    october_median <- if (is.null(october_prices)) NA_real_ else median(october_prices)
    presale <- if (is.null(november_prices) || is.na(october_median)) NA_real_ else
      (median(november_prices) - october_median) / october_median
    low <- regular <- NA_real_
    low_days <- regular_days <- 0L
    if (!is.na(start) && as_of >= event_day) {
      low_dates <- seq(start - 30, start - 1, by = "day")
      # Include September dates when a sale begins before Oct 31. The input
      # contract may not cover them; report missing coverage rather than shorten.
      low_values <- daily$price[match(low_dates, daily$date)]
      low_days <- sum(!is.na(low_values))
      if (low_days == 30L) low <- min(low_values)
      else flags <- c(flags, "incomplete_30_day_history")
      regular_dates <- if (start > min(october)) seq(min(october), start - 1, by = "day") else as.Date(character())
      regular_values <- daily$price[match(regular_dates, daily$date)]
      if (length(regular_dates) && !anyNA(regular_values) && !is.na(october_median) && campaigns_reviewed) {
        excluded <- regular_values < 0.95 * october_median
        for (j in seq_len(nrow(campaigns))) if (campaigns$platform[j] %in% c("all", platform)) {
          excluded <- excluded | (regular_dates >= as.Date(campaigns$start_date[j]) &
                                  regular_dates <= as.Date(campaigns$end_date[j]))
        }
        regular_days <- sum(!excluded)
        if (regular_days) regular <- median(regular_values[!excluded])
      }
      if (is.na(regular)) flags <- c(flags, "regular_benchmark_incomplete")
    }
    if (!campaigns_reviewed) flags <- c(flags, "campaign_calendar_needs_review")
    if (is.na(presale)) flags <- c(flags, "incomplete_presale_history")
    advertised <- discount(original, listed)
    real <- discount(low, listed)
    regular_discount <- discount(regular, listed)
    gap <- advertised - real
    gap_regular <- advertised - regular_discount
    row <- data.frame(product_id = pid, brand = metadata$brand, model = metadata$model,
      category = metadata$category, platform = platform, year = year,
      analysis_as_of = as.character(as_of), event_date = as.character(event_day),
      selected_run_id = selected_run, selected_scraped_at = selected_time,
      price_start_date = as.character(start), price_start_date_candidate = as.character(candidate),
      original_price = original, listed_price = listed, low_30d = low, regular_price = regular,
      october_median = october_median, low_30d_days = low_days, regular_days = regular_days,
      advertised_discount = advertised, real_discount = real, regular_discount = regular_discount,
      presale_change = presale, gap = gap, gap_regular = gap_regular,
      ready_h1_h3 = !is.na(gap) && !is.na(gap_regular),
      ready_h2_h4 = !is.na(real) && !is.na(regular_discount) && !is.na(presale),
      analysis_status = if (as_of < event_day) "pending_event" else
        if (!is.na(real) && !is.na(regular_discount) && !is.na(presale)) "ready_real_price" else "incomplete",
      missing_reasons = paste(unique(flags), collapse = " | "), stringsAsFactors = FALSE)
    records[[length(records) + 1L]] <- row
  }
  result <- do.call(rbind, records)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(result, file.path(output_dir, "final_analysis.csv"), row.names = FALSE, na = "NA", fileEncoding = "UTF-8")
  cat(sprintf("Analysis: %d rows | H1/H3 ready %d | H2/H4 ready %d | as of %s\n",
      nrow(result), sum(result$ready_h1_h3), sum(result$ready_h2_h4), as.character(as_of)))
  invisible(result)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  build_analysis(if (length(args) >= 1) args[1] else "output/combined/combined_snapshots.csv",
                 if (length(args) >= 2) args[2] else "output/analysis",
                 if (length(args) >= 3) args[3] else as.Date(format(Sys.time(), tz = "Asia/Taipei")))
}
