# Run from the repository root: Rscript biggo/scripts/test_build_biggo_daily.R
source("biggo/scripts/build_biggo_daily.R")

dir <- tempfile("biggo-daily-test-")
dir.create(dir)
changes_path <- file.path(dir, "changes.csv")
coverage_path <- file.path(dir, "coverage.csv")
output_path <- file.path(dir, "daily.csv")
products_path <- file.path(dir, "products.csv")
con <- file(products_path, open = "w", encoding = "UTF-8")
writeLines(c("product_id,brand,model,category", "T-1,雪芙蘭,\"Cream, 50g\",BEAU", "T-2,Acme,Cable,3C"), con)
close(con)
header <- "product_id,platform,biggo_url,changed_at,price,entered_by,entered_on,note"
write_changes <- function(rows) writeLines(c(header, rows), changes_path)
writeLines(c("product_id,platform,coverage_start,coverage_end,note",
             "T-1,momo,2025-09-01,2025-11-25,continues"), coverage_path)
build <- function(...) build_biggo_daily(changes_path, coverage_path, output_path,
                                         as.Date("2025-09-01"), as.Date("2025-09-10"),
                                         products_path = products_path, ...)

write_changes(c(
  "T-1,momo,u,2025-08-20 10:00,100,A,2026-10-25,NA",   # before the window: the opening price
  "T-1,momo,u,2025-09-03 15:07,90,A,2026-10-25,NA",    # at the slot: counts that day
  "T-1,momo,u,2025-09-05 15:08,80,A,2026-10-25,NA",    # after the slot: counts the next day
  "T-2,pchome,u,2025-09-04 09:00,50,A,2026-10-25,NA",  # first record inside the window
  "T-2,pchome,u,2025-09-06 09:00,55,A,2026-10-25,NA",  # last record, no coverage row: 15:07 that day is past it
  "T-3,coupang,u,2025-09-01 09:00,70,A,2026-10-25,NA"  # Coupang is excluded
))
d <- build()
one <- d[d$product_id == "T-1", ]
stopifnot(
  identical(names(d), c("date", "platform", "product_id", "brand", "model", "category", "price", "price_set_at")),
  identical(unique(one$model), "Cream, 50g"),
  nrow(one) == 10,                                                   # coverage carries to the window end
  one$price[one$date == "2025-09-02"] == 100,
  one$price[one$date == "2025-09-03"] == 90,
  one$price[one$date == "2025-09-05"] == 90,
  one$price[one$date == "2025-09-06"] == 80,
  one$price_set_at[one$date == "2025-09-10"] == "2025-09-05 15:08",
  identical(d$date[d$product_id == "T-2"], c("2025-09-04", "2025-09-05")),
  !any(d$platform == "coupang")
)
raw <- readBin(output_path, "raw", 400)
stopifnot(identical(raw[1:3], as.raw(c(0xEF, 0xBB, 0xBF))),  # BOM, so Excel shows the Chinese
          !any(raw == as.raw(0x0D)))                          # LF only
back <- read.csv(output_path, fileEncoding = "UTF-8", colClasses = "character")
stopifnot(names(back)[1] == "date", back$brand[back$product_id == "T-1"][1] == "雪芙蘭",
          back$model[back$product_id == "T-1"][1] == "Cream, 50g")

# Two years, each from its own file: a 2026 point must not extend a 2025 series.
changes_2026_path <- file.path(dir, "changes_2026.csv")
write_changes(c("T-2,pchome,u,2025-09-04 09:00,50,A,2026-10-25,NA",
                "T-2,pchome,u,2025-09-06 09:00,55,A,2026-10-25,NA"))
writeLines(c(header,
             "T-2,pchome,u,2025-09-06 09:00,55,M,2026-11-26,NA",   # 2026 baseline, set in 2025
             "T-2,pchome,u,2026-09-03 09:00,60,M,2026-11-26,NA",
             "T-2,pchome,u,2026-09-08 09:00,65,M,2026-11-26,NA"), changes_2026_path)
two <- build_biggo_daily(c(changes_path, changes_2026_path), coverage_path, output_path,
                         as.Date(c("2025-09-01", "2026-09-01")), as.Date(c("2025-09-10", "2026-09-10")),
                         products_path = products_path)
stopifnot(
  identical(two$date, c("2025-09-04", "2025-09-05", paste0("2026-09-0", 1:7))),
  two$price[two$date == "2026-09-01"] == 55,
  two$price[two$date == "2026-09-03"] == 60,
  two$price_set_at[two$date == "2026-09-07"] == "2026-09-03 09:00"
)

write_changes(c("T-9,momo,u,2025-09-03 12:00,90,A,2026-10-25,NA",   # not in the product table
                "T-9,momo,u,2025-09-06 12:00,80,A,2026-10-25,NA"))
stopifnot(inherits(try(build(), silent = TRUE), "try-error"))

write_changes(c("T-1,momo,u,2025-09-03 12:00,90,A,2026-10-25,NA",
                "T-1,momo,u,2025-09-03 12:00,95,A,2026-10-25,NA"))
stopifnot(inherits(try(build(), silent = TRUE), "try-error"))

write_changes("T-1,momo,u,not a time,90,A,2026-10-25,NA")
stopifnot(inherits(try(build(), silent = TRUE), "try-error"))

cat("build_biggo_daily: all tests passed\n")
