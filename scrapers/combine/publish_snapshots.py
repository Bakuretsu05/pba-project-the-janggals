"""Copy the combined snapshots into data/snapshots.csv for the analysis team.

Input: output/combined/combined_snapshots.csv, written by collect_snapshots.py.
Output: data/snapshots.csv with the 17 scraper columns of the data collection
spec (section 7.1) plus run_id, one row per scrape run x platform x product.
The provenance columns (artifact IDs, commit, run URL) stay in the
combined-snapshots Actions artifact. Also refreshes data/products.csv from
products/products.csv and the status block in data/README.md.

Git commit/push is handled by the workflow. Run from the repository root.
"""
import argparse
import csv
import io
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from collect_snapshots import SNAPSHOT_COLUMNS

COLUMNS = SNAPSHOT_COLUMNS + ["run_id"]
STATUS = re.compile(r"(<!-- status:start -->\n).*?(<!-- status:end -->)", re.S)


def read(path):
    return list(csv.DictReader(io.StringIO(path.read_bytes().decode("utf-8-sig"))))


def key(row):
    return (row["run_id"], row["platform"], row["product_id"])


def publish(combined, data_dir, products):
    rows = [{**{c: r[c] for c in SNAPSHOT_COLUMNS}, "run_id": r["source_run_id"]} for r in read(combined)]
    if not rows:
        raise ValueError("Combined snapshots are empty")
    if len({key(r) for r in rows}) != len(rows):
        raise ValueError("Duplicate run/platform/product rows in combined snapshots")
    rows.sort(key=lambda r: (r["date"], int(r["run_id"]), r["platform"], r["product_id"]))

    target = data_dir / "snapshots.csv"
    if target.exists():
        missing = {key(r) for r in read(target)} - {key(r) for r in rows}
        if missing:
            raise ValueError(f"Refusing to drop {len(missing)} published observations, e.g. {sorted(missing)[0]}")

    data_dir.mkdir(parents=True, exist_ok=True)
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=COLUMNS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    target.write_bytes(buffer.getvalue().encode("utf-8"))
    # Until the scrapers read data/products.csv directly (after Nov 12), keep a copy here.
    shutil.copyfile(products, data_dir / "products.csv")

    runs = {r["run_id"] for r in rows}
    latest = max(r["date"] for r in rows)
    readme = data_dir / "README.md"
    if readme.exists():
        text = readme.read_text(encoding="utf-8")
        status = (f"- `snapshots.csv`: **{len(rows):,} rows** from **{len(runs)} scrape runs**, "
                  f"latest collection **{latest}** (Taiwan date)\n")
        updated = STATUS.sub(lambda m: m[1] + status + m[2], text)
        if updated == text and status not in text:
            raise ValueError("data/README.md lacks the status markers")
        readme.write_text(updated, encoding="utf-8", newline="\n")
    print(f"Published {len(rows)} snapshot rows from {len(runs)} runs; latest {latest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--combined", type=Path, default=Path("output/combined/combined_snapshots.csv"))
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--products", type=Path, default=Path("products/products.csv"))
    args = parser.parse_args()
    publish(args.combined, args.data_dir, args.products)
