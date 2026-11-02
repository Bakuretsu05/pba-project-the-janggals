# scrapers/

The code that produces [`data/snapshots.csv`](../data/snapshots.csv): our own daily price
snapshots of every product on momo and PChome, Oct 19 to Nov 25, 2026.

| Folder | What it is |
|---|---|
| [`momo/`](momo/) | The momo scraper |
| [`pchome/`](pchome/) | The PChome scraper |
| [`combine/`](combine/) | Merges every scrape run into one table and publishes it as `data/snapshots.csv` |

Everything a scraper must do is in **[`data-collection-spec.md`](data-collection-spec.md)**:
input, output columns, failure handling, schedule, rules and acceptance criteria. If your code
and the spec disagree, the spec wins; if the spec is wrong, change it and tell the group.

## How a day's data reaches `data/`

1. **scrape** (`.github/workflows/scrape.yml`) runs both scrapers at 15:07 Taiwan time (and at
   18:07 and 23:07 on Nov 10-12). Each run saves its CSV and raw pages as an Actions artifact.
2. **combined snapshots** (`.github/workflows/combined-snapshots.yml`) starts when a scrape
   finishes. `combine/collect_snapshots.py` adds the new run to the cumulative table, and
   `combine/publish_snapshots.py` writes `data/snapshots.csv` and commits it.

The cumulative table with full provenance (artifact IDs, commit, run URL) and a per-run summary
stay in the `combined-snapshots` artifact of each run.

The Coupang scraper was retired on 2026-10-20 and removed from the repo on 2026-11-02; it is in
git history at commit `4b97f51`.
