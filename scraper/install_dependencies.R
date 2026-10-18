#!/usr/bin/env Rscript
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- dirname(dirname(normalizePath(sub("^--file=", "", script_arg[[1L]]), winslash = "/", mustWork = TRUE)))
target <- file.path(root, ".R-library")
dir.create(target, showWarnings = FALSE, recursive = TRUE)
.libPaths(c(target, .libPaths()))
packages <- c("httr2", "rvest", "jsonlite")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, lib = target, repos = "https://cloud.r-project.org")
if (!all(vapply(packages, requireNamespace, logical(1), quietly = TRUE))) stop("Dependency installation failed")
cat("R dependencies ready: ", paste(packages, collapse = ", "), "\n", sep = "")

