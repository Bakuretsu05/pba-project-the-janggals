# analysis/

The analysis code goes here: the R scripts or Quarto documents that turn the files in
[`data/`](../data/) into figures, tables and regressions for the milestones and the final report.

## Rules that keep it runnable from the repo

- **Read the data with relative paths.** Quarto runs a document from its own folder, so from
  here the data is `../data/scrapes.csv`, `../data/biggo.csv` and `../data/products.csv`.
  Never `setwd()` or a path on your own laptop (`C:/Users/...`): it breaks for everyone else.
- **Don't copy or edit the data here.** `data/` is generated; build what you need in code.
  [`data/README.md`](../data/README.md) is the codebook: what each column means and how to load it.
- **Commit the code, and the figures if they are small.** Anyone who clones the repo should be able
  to rerun your file and get the same figure.
- **No raw data.** The saved web pages stay in GitHub Actions, out of this public repo.
