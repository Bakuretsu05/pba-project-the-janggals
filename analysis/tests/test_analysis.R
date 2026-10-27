if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
source("analysis/build_analysis.R", encoding = "UTF-8")
root <- tempfile("analysis-test-")
dir.create(root)
dir.create(file.path(root, "config"))
put <- function(x, name) write.csv(x, file.path(root, name), row.names = FALSE, na = "NA", fileEncoding = "UTF-8")
put(data.frame(product_id = "3C-001", brand = "test", model = "same variant", category = "3C"), "products.csv")
put(data.frame(product_id = character(), platform = character(), coverage_start = character(),
               coverage_end = character(), note = character()), "config/history_coverage.csv")
put(data.frame(platform = "all", start_date = "2026-11-01", end_date = "2026-11-10", note = "test campaign"),
    "config/campaign_periods.csv")
decisions <- data.frame(product_id = "3C-001", platform = "momo", year = 2026,
                       price_start_date = "2026-11-11", snapshot_run_id = NA_character_,
                       campaigns_reviewed = TRUE, note = "reviewed")
put(decisions, "config/event_decisions.csv")
dates <- seq(as.Date("2026-10-01"), as.Date("2026-11-25"), by = "day")
history <- data.frame(product_id = "3C-001", platform = "momo", changed_at = paste(dates, "15:07:00"),
                      price = ifelse(dates >= as.Date("2026-11-11"), 80,
                                     ifelse(dates >= as.Date("2026-11-01"), 110, 100)))
put(history, "history.csv")
snapshots <- data.frame(product_id = "3C-001", platform = "momo", date = "2026-11-11",
                       scraped_at = c("2026-11-11 15:08:00", "2026-11-11 18:08:00"),
                       original_price = 200, sale_price = 90, extra_price = c(80, 70),
                       extra_price_label = "\u9650\u6642\u6298\u5f8c\u50f9", fetch_status = "ok", source_run_id = c("1", "2"))
put(snapshots, "snapshots.csv")
build <- function(as_of = "2026-11-25") build_analysis(file.path(root, "snapshots.csv"),
  file.path(root, "out"), as_of, file.path(root, "products.csv"), file.path(root, "history.csv"), file.path(root, "config"))
pick <- function(x) x[x$platform == "momo" & x$year == 2026, ]
x <- build()
stopifnot(nrow(x) == 4L)
r <- pick(x)
stopifnot(r$selected_run_id == "1", r$listed_price == 80, r$low_30d == 100,
          r$regular_price == 100, r$low_30d_days == 30L, r$ready_h1_h3,
          abs(r$advertised_discount - 0.6) < 1e-9, abs(r$gap - 0.4) < 1e-9,
          abs(r$presale_change - 0.1) < 1e-9)
stopifnot(r$latest_run_id == "2", r$latest_listed_price == 70,
          r$latest_sale_price == 90, r$observed_snapshot_count == 2L,
          r$observed_ok_count == 2L, r$observed_days == 1L,
          r$observed_min_listed_price == 70, r$observed_max_listed_price == 80)

# The latest preview preserves failures; it never silently fills from an older
# successful run, includes future observations, or borrows another year's prices.
preview_input <- snapshots
preview_input$date <- c("2026-10-25", "2026-10-26")
preview_input$scraped_at <- c("2026-10-25 15:08:00", NA_character_)
preview_input$run_started_at <- c("2026-10-25_1508", "2026-10-26_1508")
preview_input$fetch_status[2] <- "parse_failure"
future <- preview_input[1, ]
future$date <- "2026-10-27"
future$scraped_at <- "2026-10-27 15:08:00"
future$source_run_id <- "3"
p <- snapshot_preview(rbind(preview_input, future), "3C-001", "momo", 2026, as.Date("2026-10-26"))
stopifnot(p$latest_snapshot_date == "2026-10-26", p$latest_run_id == "2",
          p$latest_fetch_status == "parse_failure", is.na(p$latest_sale_price),
          is.na(p$latest_listed_price), p$observed_snapshot_count == 2L,
          p$observed_ok_count == 1L, p$observed_days == 2L,
          p$observed_min_listed_price == 80)
p <- snapshot_preview(preview_input, "3C-001", "momo", 2025, as.Date("2026-10-26"))
stopifnot(p$observed_snapshot_count == 0L, is.na(p$latest_listed_price))

# Missing original prices do not prevent real-discount analysis.
snapshots$original_price <- NA_real_
put(snapshots, "snapshots.csv")
r <- pick(build())
stopifnot(is.na(r$gap), !r$ready_h1_h3, r$ready_h2_h4, r$real_discount == 0.2)

# A failed first run must not be substituted with a later successful flash sale.
snapshots$fetch_status[1] <- "blocked"
put(snapshots, "snapshots.csv")
stopifnot(is.na(pick(build())$listed_price))
snapshots$fetch_status[1] <- "ok"
snapshots$extra_price_label <- "\u6703\u54e1\u5238\u5f8c\u50f9"
put(snapshots, "snapshots.csv")
stopifnot(pick(build())$listed_price == 90)

# Before Nov 11 the 2026 event must stay pending, regardless of future fixture rows.
r <- pick(build("2026-10-26"))
stopifnot(is.na(r$listed_price), is.na(r$low_30d), r$analysis_status == "pending_event")

# Without reviewed event onset/calendar, no guessed benchmarks are published.
decisions$price_start_date <- NA_character_
decisions$campaigns_reviewed <- FALSE
put(decisions, "config/event_decisions.csv")
snapshots$extra_price_label <- "\u9650\u6642\u6298\u5f8c\u50f9"
put(snapshots, "snapshots.csv")
r <- pick(build())
stopifnot(is.na(r$low_30d), is.na(r$regular_price), r$price_start_date_candidate == "2026-11-11")

# Do not carry a price beyond the last observed point without coverage evidence.
short <- history[history$changed_at <= "2026-10-20 15:07:00", ]
daily <- daily_history(short, read.csv(file.path(root, "config/history_coverage.csv")),
                       "3C-001", "momo", 2026, as.Date("2026-11-25"))
stopifnot(is.na(daily$price[daily$date == as.Date("2026-10-21")]))

# 2025 has real-price measures but must never borrow a 2026 reference price.
historical <- history
historical$changed_at <- sub("2026", "2025", historical$changed_at)
put(rbind(historical, history), "history.csv")
past_decision <- decisions
past_decision$year <- 2025
past_decision$price_start_date <- "2025-11-11"
past_decision$campaigns_reviewed <- TRUE
put(rbind(decisions, past_decision), "config/event_decisions.csv")
x <- build()
past <- x[x$platform == "momo" & x$year == 2025, ]
stopifnot(past$listed_price == 80, past$real_discount == 0.2, is.na(past$advertised_discount),
          is.na(past$gap), past$ready_h2_h4, !past$ready_h1_h3)
cat("All analysis tests passed\n")
unlink(root, recursive = TRUE)
