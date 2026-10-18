#!/usr/bin/env Rscript
# Run from the repo root: Rscript scraper/scrape_momo.R
if (.Platform$OS.type == "windows" && !isTRUE(l10n_info()[["UTF-8"]]))
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]), winslash = "/", mustWork = TRUE)
root <- dirname(dirname(script_path))
local_library <- file.path(root, ".R-library")
if (dir.exists(local_library)) .libPaths(c(local_library, .libPaths()))
for (package in c("httr2", "rvest", "jsonlite")) {
  if (!requireNamespace(package, quietly = TRUE))
    stop("Missing R package ", package, ". Run Rscript scraper/install_dependencies.R")
}
source(file.path(root, "scraper", "momo.R"), encoding = "UTF-8")
if (file.exists(file.path(root, ".Renviron"))) readRenviron(file.path(root, ".Renviron"))
contact <- Sys.getenv("PBA_CONTACT_EMAIL")
if (!nzchar(contact) || grepl("[\r\n]", contact) || !grepl("^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$", contact))
  stop("Set PBA_CONTACT_EMAIL in .Renviron; see .Renviron.example")
args <- commandArgs(trailingOnly = TRUE)
options <- list(products = file.path(root, "data", "products.csv"),
  output_dir = file.path(root, "data", "snapshots"), raw_dir = file.path(root, "raw"),
  log_dir = file.path(root, "data", "logs"), limit = NULL, ids = NULL)
if (length(args) %% 2L != 0L) stop("Options require values: --products, --output-dir, --raw-dir, --log-dir, --limit, --ids")
if (length(args)) for (i in seq(1L, length(args), 2L)) {
  key <- gsub("-", "_", sub("^--", "", args[[i]]))
  if (!key %in% names(options)) stop("Unknown option: ", args[[i]])
  options[key] <- list(args[[i + 1L]])
}
products <- momo_read_products(options$products)
if (!is.null(options$ids)) {
  ids <- strsplit(options$ids, ",", fixed = TRUE)[[1L]]
  if (any(!ids %in% products$product_id)) stop("--ids contains an unknown/unconfirmed product")
  products <- products[products$product_id %in% ids, , drop = FALSE]
}
if (!is.null(options$limit)) {
  count <- suppressWarnings(as.integer(options$limit))
  if (is.na(count) || count < 1L || as.character(count) != options$limit) stop("--limit must be a positive integer")
  products <- head(products, count)
}
user_agent <- paste0("PBA-Double11-study (NTHU ISS4066; contact: ", contact, ")")
result <- momo_run(products, options$output_dir, options$raw_dir, options$log_dir, momo_client(user_agent))
# Failed products still have rows; a nonzero exit signals attention is needed.
if (result$failures > 0L || result$stopped) quit(status = 1L)

