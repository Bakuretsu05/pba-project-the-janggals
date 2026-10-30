"""Prepare only the latest analysis CSV and its guide for publication to Git.

Git commit/push is handled by the workflow, which checks out current main in a
separate job. Verify the build inputs first, so an older build cannot silently
publish results calculated from different code, products, history or decisions.
"""
import argparse
import csv
import hashlib
import io
import json
import subprocess
from datetime import date
from pathlib import Path

INPUTS = (
    "products/products.csv", "biggo/price_changes.csv", "analysis/build_analysis.R",
    "analysis/config/event_decisions.csv", "analysis/config/history_coverage.csv",
    "analysis/config/campaign_periods.csv",
)


def git_blob(root, name):
    return subprocess.check_output(["git", "-C", str(root), "show", "HEAD:" + name])


def records(data):
    return list(csv.DictReader(io.StringIO(data.decode("utf-8-sig"))))


def prepare(artifact_dir, destination, repo_root):
    manifest = json.loads((artifact_dir / "build_manifest.json").read_text(encoding="utf-8"))
    for name in INPUTS:
        digest = hashlib.sha256(git_blob(repo_root, name)).hexdigest()
        if manifest["sha256"].get(name) != digest:
            raise ValueError(f"Build input changed on main: {name}; rebuild before publishing")
    raw = (artifact_dir / "final_analysis.csv").read_bytes()
    rows = records(raw)
    required = {"product_id", "platform", "year", "analysis_as_of", "analysis_status", "latest_snapshot_date"}
    if not rows or not required.issubset(rows[0]):
        raise ValueError("Analysis CSV is empty or missing required columns")
    products = records(git_blob(repo_root, "products/products.csv"))
    expected = {(p["product_id"], platform, str(year)) for p in products
                for platform in ("momo", "pchome") for year in (2025, 2026)}
    keys = [(r["product_id"], r["platform"], r["year"]) for r in rows]
    if len(keys) != len(set(keys)) or set(keys) != expected:
        raise ValueError("Analysis CSV has duplicate or missing product/platform/year rows")
    as_of_values = {r["analysis_as_of"] for r in rows}
    if len(as_of_values) != 1:
        raise ValueError("Analysis CSV has inconsistent as-of dates")
    as_of = next(iter(as_of_values))
    date.fromisoformat(as_of)
    available = [r["latest_snapshot_date"] for r in rows if r["latest_snapshot_date"] not in ("", "NA")]
    latest = max(available) if available else "not available"
    if available:
        date.fromisoformat(latest)
        if latest > as_of:
            raise ValueError("Snapshot date is after the analysis as-of date")
    previous = destination / "final_analysis.csv"
    if previous.exists():
        old = records(previous.read_bytes())
        if old and max(r["analysis_as_of"] for r in old) > as_of:
            raise ValueError("Refusing to replace a newer published analysis table")
        old_dates = [r["latest_snapshot_date"] for r in old if r["latest_snapshot_date"] not in ("", "NA")]
        if old_dates and (not available or max(old_dates) > latest):
            raise ValueError("Refusing to replace more recent snapshot data")
        old_by_key = {(r["product_id"], r["platform"], r["year"]): r for r in old}
        for row in rows:
            prior = old_by_key.get((row["product_id"], row["platform"], row["year"]), {})
            old_time = prior.get("latest_scraped_at", "NA")
            new_time = row.get("latest_scraped_at", "NA")
            if old_time not in ("", "NA") and new_time not in ("", "NA") and old_time > new_time:
                raise ValueError("Refusing to replace a newer observation with an earlier run")
            if int(prior.get("observed_snapshot_count", 0)) > int(row.get("observed_snapshot_count", 0)):
                raise ValueError("Refusing to publish a shorter snapshot history")
    guide = f"""# Latest analysis data

[Download the CSV](final_analysis.csv) or browse it directly on GitHub.

- **Analysis as of (Taiwan date): {as_of}**
- **Latest collected snapshot date: {latest}**
- **Rows: {len(rows)}** (one product x platform x year)

This is the latest cumulative analysis view. The automatic analysis workflow
replaces this same file after a real collection or an analysis-input update.
Only changed CSV/README contents are committed; skipped backup runs do not
publish data. Earlier versions remain available in Git history.

## Reading the table

- Filter `year = 2026` and use `latest_*` columns for current momo/PChome
  observations. `latest_fetch_status` identifies failures; missing current prices
  are not replaced with older successful prices.
- Filter `year = 2025` and use `listed_price`, `october_median` and
  `presale_change` for available BigGo historical measures.
- The unprefixed price/discount/gap columns describe the November 11 research
  event. The current-price preview is kept separate from those outcomes.
- `NA` means unavailable or not yet calculable, not zero. Consult
  `missing_reasons`, `analysis_status` and `ready_*` before analysing results.
- Discount rates are fractions: `0.20` means 20%; a gap of `0.10` means
  10 percentage points. Widen date columns if Excel shows `########`.

For definitions, assumptions and review requirements, see
[the analysis guide](../analysis/README.md). Individual platform CSVs, cumulative
snapshots, raw pages and build manifests remain in the GitHub Actions artifacts;
they are not copied into this directory. Existing unrelated data folders are
preserved. This CSV contains both current observations and provisional results;
its filename does not imply that all hypothesis tests are ready.
"""
    destination.mkdir(parents=True, exist_ok=True)
    # Match repository line endings across Windows seeding and Linux rebuilds.
    (destination / "final_analysis.csv").write_bytes(raw.replace(b"\r\n", b"\n"))
    (destination / "README.md").write_text(guide, encoding="utf-8", newline="\n")
    print(f"Prepared {len(rows)} analysis rows; latest snapshot {latest}; as of {as_of}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact-dir", type=Path, default=Path("output/analysis"))
    parser.add_argument("--destination", type=Path, default=Path("data"))
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    args = parser.parse_args()
    prepare(args.artifact_dir, args.destination, args.repo_root)
