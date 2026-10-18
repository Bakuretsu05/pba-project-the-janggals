# A minimal test runner (base R only) and builders for saved run folders, shared by the tests in
# this folder. The fixture pages in fixtures/ are markup copied from real Coupang pages.

FIXTURES <- "scrapers/coupang/tests/fixtures"

.results <- new.env()
.results$failed <- character()
.results$passed <- 0L

test <- function(name, code) {
  outcome <- tryCatch({
    force(code)
    NULL
  }, error = function(e) conditionMessage(e))
  if (is.null(outcome)) {
    .results$passed <- .results$passed + 1L
    cat("ok    ", name, "\n", sep = "")
  } else {
    .results$failed <- c(.results$failed, name)
    cat("FAIL  ", name, "\n      ", outcome, "\n", sep = "")
  }
}

expect_equal <- function(actual, expected) {
  if (!identical(actual, expected)) {
    stop(sprintf("%s is %s, expected %s", deparse(substitute(actual)),
                 paste(deparse(actual), collapse = ""), paste(deparse(expected), collapse = "")),
         call. = FALSE)
  }
}

expect_true <- function(condition) {
  if (!isTRUE(condition)) stop(deparse(substitute(condition)), " is not TRUE", call. = FALSE)
}

expect_error <- function(code, pattern) {
  message <- tryCatch({
    force(code)
    NULL
  }, error = function(e) conditionMessage(e))
  if (is.null(message)) stop("expected an error matching '", pattern, "', got none", call. = FALSE)
  if (!grepl(pattern, message)) stop("error '", message, "' does not match '", pattern, "'", call. = FALSE)
}

report <- function() {
  cat(sprintf("\n%d passed, %d failed\n", .results$passed, length(.results$failed)))
  quit(save = "no", status = if (length(.results$failed) > 0) 1 else 0)
}

gz_text <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  txt <- rawToChar(readBin(con, "raw", 1e7))
  Encoding(txt) <- "UTF-8"
  txt
}

fixture_page <- function(name) {
  path <- file.path(FIXTURES, paste0(name, ".html"))
  txt <- rawToChar(readBin(path, "raw", file.info(path)$size))
  Encoding(txt) <- "UTF-8"
  txt
}

# ---- Saved run folders, as the Chrome extension writes them ---------------------------------------

attempt <- function(sent, status = 200, page = NULL, error = NULL) {
  list(sent = sent, status = status, page = page, error = error)
}

product <- function(product_id, item_id, attempts = list(), url = NULL) {
  if (is.null(url)) {
    url <- sprintf("https://www.tw.coupang.com/products/1?itemId=%s&vendorItemId=2", item_id)
  }
  list(product_id = product_id, item_id = item_id, url = url, attempts = attempts)
}

# Writes <temp>/<stamp>/ with products.csv, one .html.gz per attempt that got a body, and run.json.
# `extra_rows` are product table rows the extension did not request (e.g. bad input).
saved_run <- function(stamp, products, state = "finished", extra_rows = list(), table = TRUE,
                      error = NULL, parent = tempfile("saved")) {
  run_dir <- file.path(parent, stamp)
  dir.create(run_dir, recursive = TRUE)
  table_rows <- c(lapply(products, function(p) c(p$product_id, p$url)), extra_rows)
  if (table) {
    lines <- c(paste(INPUT_COLUMNS, collapse = ","),
               vapply(table_rows, function(r) sprintf("%s,b,m,3C,,,%s,,,", r[1], r[2]), ""))
    writeLines(enc2utf8(lines), file.path(run_dir, "products.csv"), useBytes = TRUE)
  }
  entries <- lapply(products, function(p) {
    attempts <- lapply(seq_along(p$attempts), function(k) {
      a <- p$attempts[[k]]
      sent <- as.POSIXct(a$sent, tz = "Asia/Taipei")
      file <- NULL
      if (!is.null(a$page)) {
        file <- sprintf("%s_try%d.html.gz", p$item_id, k)
        con <- gzfile(file.path(run_dir, file), "wb")
        writeBin(charToRaw(enc2utf8(a$page)), con)
        close(con)
      }
      list(sent_ms = as.numeric(sent) * 1000, sent_at = a$sent, status = a$status,
           error = a$error, file = file)
    })
    list(product_id = p$product_id, item_id = p$item_id, url = p$url, attempts = attempts)
  })
  record <- list(format = 1, stamp = stamp, kind = "scheduled", state = state, error = error,
                 target_count = length(products), products = entries)
  writeLines(toJSON(record, auto_unbox = TRUE, null = "null", digits = NA),
             file.path(run_dir, "run.json"), useBytes = TRUE)
  run_dir
}

# Imports `run_dir` into a temporary output/ and raw/ and reads the CSV back as the analysis will.
import_into_temp <- function(run_dir, out_dir = tempfile("output"), raw_root = tempfile("raw")) {
  import_saved_run(run_dir, out_dir = out_dir, raw_root = raw_root)
  file <- file.path(out_dir, sprintf("coupang_%s.csv", basename(run_dir)))
  read.csv(file, fileEncoding = "UTF-8", colClasses = c(platform_item_id = "character"))
}
