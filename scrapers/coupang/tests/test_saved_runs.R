# Tests of the --saved mode of scrape_coupang.R: a run folder saved by the Chrome extension in,
# the run's CSV rows and raw/ files out. Run from the project root (by relative path, see README):
#
#   Rscript scrapers/coupang/tests/test_saved_runs.R

source("scrapers/coupang/scrape_coupang.R")
source("scrapers/coupang/tests/helpers.R")

# ---- A run with one product page ------------------------------------------------------------------

test("a saved product page becomes an ok row with the prices shown", {
  run_dir <- saved_run("2026-10-19_1007", products = list(
    product("TEST-001", "497204175273987", attempts = list(
      attempt(sent = "2026-10-19 10:07:13", status = 200, page = fixture_page("airpods"))))))
  rows <- import_into_temp(run_dir)

  expect_equal(nrow(rows), 1L)
  expect_equal(rows$date, "2026-10-19")
  expect_equal(rows$scraped_at, "2026-10-19 10:07:13")
  expect_equal(rows$platform_item_id, "497204175273987")
  expect_equal(rows$original_price, 4490L)
  expect_equal(rows$sale_price, 3590L)
  expect_equal(rows$extra_price, 3410L)
  expect_equal(rows$extra_price_label, "王道卡 特惠價")
  expect_equal(rows$promo_tag, "8折")
  expect_equal(rows$seller_type, "platform")
  expect_equal(rows$in_stock, TRUE)
  expect_equal(rows$http_status, 200L)
  expect_equal(rows$source, "scraper")
  expect_equal(rows$fetch_status, "ok")
})

test("every saved body goes to raw/, the one the row was read from as <itemId>.html.gz", {
  run_dir <- saved_run("2026-10-19_1007", products = list(
    product("TEST-002", "220665340723205", attempts = list(
      attempt(sent = "2026-10-19 10:07:13", status = 503, page = "<html>busy</html>"),
      attempt(sent = "2026-10-19 10:08:14", status = 200, page = fixture_page("first_purchase"))))))
  raw_root <- tempfile("raw")
  rows <- import_into_temp(run_dir, raw_root = raw_root)

  raw_dir <- file.path(raw_root, "2026-10-19_1007")
  expect_equal(sort(list.files(raw_dir)), c("220665340723205.html.gz", "220665340723205_1.html.gz"))
  expect_equal(gz_text(file.path(raw_dir, "220665340723205_1.html.gz")), "<html>busy</html>")
  expect_equal(gz_text(file.path(raw_dir, "220665340723205.html.gz")), fixture_page("first_purchase"))
  expect_equal(rows$scraped_at, "2026-10-19 10:08:14")
  expect_equal(rows$http_status, 200L)
  expect_equal(rows$sale_price, 199L)
  expect_equal(rows$extra_price, 1L)
  expect_equal(rows$extra_price_label, "首購折扣價")
})

# ---- Products that did not end ok (section 8.1) ----------------------------------------------------

test("a link without itemId gets a bad_input row", {
  run_dir <- saved_run("2026-10-19_1007", products = list(),
    extra_rows = list(c("TEST-005", "https://www.tw.coupang.com/products/613522857558103?vendorItemId=497204175290369")))
  rows <- import_into_temp(run_dir)

  expect_equal(rows$product_id, "TEST-005")
  expect_equal(rows$fetch_status, "bad_input")
  expect_equal(rows$scraped_at, NA)
  expect_equal(rows$platform_item_id, NA_character_)
})

test("a product the run never reached gets a timeout row without a request time", {
  run_dir <- saved_run("2026-10-19_1007", state = "interrupted", products = list(
    product("TEST-001", "497204175273987", attempts = list(
      attempt(sent = "2026-10-19 10:07:13", status = 200, page = fixture_page("airpods")))),
    product("TEST-002", "220665340723205")))
  rows <- import_into_temp(run_dir)

  expect_equal(rows$fetch_status, c("ok", "timeout"))
  expect_equal(rows$scraped_at, c("2026-10-19 10:07:13", NA))
  expect_equal(rows$http_status, c(200L, NA))
})

test("a page Akamai refused is blocked, with its status", {
  run_dir <- saved_run("2026-10-19_1007", products = list(
    product("TEST-001", "497204175273987", attempts = list(
      attempt(sent = "2026-10-19 10:07:13", status = 403, page = fixture_page("access_denied"))))))
  rows <- import_into_temp(run_dir)

  expect_equal(rows$fetch_status, "blocked")
  expect_equal(rows$http_status, 403L)
  expect_equal(rows$sale_price, NA)
})

test("no response after the retry is a timeout, timed at the retry", {
  run_dir <- saved_run("2026-10-19_1007", products = list(
    product("TEST-001", "497204175273987", attempts = list(
      attempt(sent = "2026-10-19 10:07:13", status = NULL, error = "timeout"),
      attempt(sent = "2026-10-19 10:08:43", status = NULL, error = "timeout")))))
  rows <- import_into_temp(run_dir)

  expect_equal(rows$fetch_status, "timeout")
  expect_equal(rows$http_status, NA)
  expect_equal(rows$scraped_at, "2026-10-19 10:08:43")
})

test("Coupang's 找不到商品 page (wrong or dead link) is a parse_failure", {
  run_dir <- saved_run("2026-10-19_1007", products = list(
    product("TEST-004", "100000000000001", attempts = list(
      attempt(sent = "2026-10-19 10:07:13", status = 200, page = fixture_page("not_found"))))))
  rows <- import_into_temp(run_dir)

  expect_equal(rows$fetch_status, "parse_failure")
  expect_equal(rows$http_status, 200L)
})

# ---- Whole runs ------------------------------------------------------------------------------------

one_ok_product <- function() {
  list(product("TEST-001", "497204175273987", attempts = list(
    attempt(sent = "2026-10-19 10:07:13", status = 200, page = fixture_page("airpods")))))
}

test("importing a run a second time stops and leaves the first CSV as it was", {
  run_dir <- saved_run("2026-10-19_1007", products = one_ok_product())
  out_dir <- tempfile("output")
  import_saved_run(run_dir, out_dir = out_dir, raw_root = tempfile("raw"))
  file <- file.path(out_dir, "coupang_2026-10-19_1007.csv")
  before <- readLines(file, encoding = "UTF-8")

  expect_error(import_saved_run(run_dir, out_dir = out_dir, raw_root = tempfile("raw")), "already exists")
  expect_equal(readLines(file, encoding = "UTF-8"), before)
})

test("a run that could not get its product table writes no CSV", {
  run_dir <- saved_run("2026-10-19_1007", products = list(), table = FALSE, state = "failed",
                       error = "could not download the product table (HTTP 404)")
  out_dir <- tempfile("output")

  expect_error(import_saved_run(run_dir, out_dir = out_dir, raw_root = tempfile("raw")), "HTTP 404")
  expect_equal(list.files(out_dir), character())
})

test("import_saved_runs() imports each saved run once and leaves runs still being saved", {
  saved <- tempfile("saved")
  saved_run("2026-10-19_1007", products = one_ok_product(), parent = saved)
  dir.create(file.path(saved, "2026-10-20_1007"))  # no run.json yet: Chrome is still saving it
  out_dir <- tempfile("output")
  raw_root <- tempfile("raw")

  first <- import_saved_runs(saved, out_dir = out_dir, raw_root = raw_root)
  expect_equal(list.files(out_dir), "coupang_2026-10-19_1007.csv")
  expect_true(first$ok)
  expect_true(any(grepl("^coupang: 1 products \\| ok 1 \\|", first$lines)))
  expect_true(any(grepl("2026-10-20_1007", first$lines)))

  second <- import_saved_runs(saved, out_dir = out_dir, raw_root = raw_root)
  expect_equal(list.files(out_dir), "coupang_2026-10-19_1007.csv")
  expect_true(!any(grepl("2026-10-19_1007", second$lines)))
})

test("import_saved_runs() reports a run with no ok row as not ok (FR-9)", {
  saved <- tempfile("saved")
  saved_run("2026-10-19_1007", parent = saved, products = list(
    product("TEST-001", "497204175273987", attempts = list(
      attempt(sent = "2026-10-19 10:07:13", status = 403, page = fixture_page("access_denied"))))))

  result <- import_saved_runs(saved, out_dir = tempfile("output"), raw_root = tempfile("raw"))
  expect_true(!result$ok)
})

report()
