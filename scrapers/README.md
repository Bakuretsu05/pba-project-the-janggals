# Scrapers

One folder per platform, each owned by one person:

| Folder | Owner |
|---|---|
| [`momo/`](momo/) | Jordan |
| [`pchome/`](pchome/) | Albert |
| [`coupang/`](coupang/) | Marvin |

Everything a scraper must do is in **[`data-collection-spec.md`](data-collection-spec.md)**:
input, output columns, failure handling, schedule, rules and acceptance criteria. If your code
and the spec disagree, the spec wins; if the spec is wrong, change it and tell the group.
