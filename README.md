# pba-project-the-janggals

Team **The Janggals**, ISS4066 Programming for Business Analytics, NTHU, Fall 2026.

## Topic

Are Double 11 discounts real? We track 150 products on momo and PChome and compare each Nov 11
"discount" with the product's lowest price in the previous 30 days (the EU benchmark), using
BigGo price history for 2025 and 2026 plus our own daily snapshots of each momo and PChome
page's crossed-out "original price".

## Team

- Marvin Chandra
- Jordan Tjiang
- Alicia Joely
- Audrey Priscilla Wijaya
- Nicholas Albert Aklin

## Where things are

**The data is in [`data/`](data/).** Start with [`data/README.md`](data/README.md): it lists each
file, what one row means and how to load it in R. Every other folder holds the code and notes
that produced the data.

| Folder | What it is |
|---|---|
| [`data/`](data/) | Everything the analysis needs: products, our 2026 snapshots, BigGo's 2025 history |
| [`scrapers/`](scrapers/) | The momo and PChome scrapers, the data collection spec, and the step that publishes `data/snapshots.csv` |
| [`biggo/`](biggo/) | How the BigGo price history was collected and checked |
| [`products/`](products/) | How the 150 products were chosen; `products/products.csv` is the table the scrapers read |
| [`.github/workflows/`](.github/workflows/) | The automation: daily scrapes, publishing to `data/`, tests |

Everything a collector must do is in [`scrapers/data-collection-spec.md`](scrapers/data-collection-spec.md).
