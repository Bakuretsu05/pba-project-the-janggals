"""Recover CSVs from scrape artifacts; retain a cumulative, provenance-rich ledger.

Only Python's standard library and the authenticated GitHub CLI are required.
Raw HTML ZIP members are never extracted or executed.
"""
import argparse
import base64
import csv
import io
import json
import re
import subprocess
import zipfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

SNAPSHOT_COLUMNS = [
    "date", "scraped_at", "platform", "product_id", "platform_item_id",
    "original_price", "sale_price", "extra_price", "extra_price_label",
    "shown_discount_pct", "promo_tag", "coupon_note", "seller_type", "in_stock",
    "http_status", "source", "fetch_status",
]
META_COLUMNS = ["snapshot_id", "source_run_id", "source_run_attempt", "source_run_url",
                "source_head_sha", "source_artifact_id", "source_artifact_name",
                "run_started_at", "source_run_conclusion", "brand", "model", "category"]
ARTIFACT_RE = re.compile(r"^(momo|pchome)_(\d{4}-\d{2}-\d{2}_\d{4})$")
STATUSES = {"ok", "parse_failure", "http_error", "timeout", "blocked", "bad_input"}


def api(repo, endpoint, paginate=False):
    command = ["gh", "api"]
    if paginate:
        command += ["--paginate", "--slurp"]
    command += [f"repos/{repo}/{endpoint}"]
    return subprocess.check_output(command)


def pages(repo, endpoint, key):
    return [row for page in json.loads(api(repo, endpoint, True)) for row in page[key]]


def read_csv_bytes(data):
    return list(csv.DictReader(io.StringIO(data.decode("utf-8-sig"))))


def csv_member(data, filename):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        matches = [n for n in archive.namelist() if Path(n).name == filename]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one {filename}, found {matches}")
        return archive.read(matches[0])


def parse_snapshot(data, artifact, run, products):
    platform, stamp = ARTIFACT_RE.fullmatch(artifact["name"]).groups()
    rows = read_csv_bytes(data)
    if not rows:
        raise ValueError("Empty scraper CSV")
    if not set(SNAPSHOT_COLUMNS).issubset(rows[0]):
        raise ValueError("Scraper CSV is missing required columns")
    seen = set()
    result = []
    for row in rows:
        pid = row["product_id"]
        if pid in seen or not pid:
            raise ValueError(f"Duplicate/empty product_id: {pid}")
        seen.add(pid)
        if row["platform"] != platform or row["date"] != stamp[:10]:
            raise ValueError("Artifact platform/date disagrees with its CSV")
        if row["fetch_status"] not in STATUSES:
            raise ValueError(f"Unknown fetch status: {row['fetch_status']}")
        for field in ("original_price", "sale_price", "extra_price"):
            if row[field] not in ("", "NA") and (not row[field].isdigit() or int(row[field]) < 0):
                raise ValueError(f"Invalid {field}: {row[field]}")
        if row["scraped_at"] not in ("", "NA"):
            datetime.strptime(row["scraped_at"], "%Y-%m-%d %H:%M:%S")
        product = products.get(pid, {})
        result.append({**{k: row[k] or "NA" for k in SNAPSHOT_COLUMNS},
                       "snapshot_id": f"{run['id']}:{platform}:{stamp}",
                       "source_run_id": str(run["id"]),
                       "source_run_attempt": str(run["run_attempt"]),
                       "source_run_url": run["html_url"], "source_head_sha": run["head_sha"],
                       "source_artifact_id": str(artifact["id"]),
                       "source_artifact_name": artifact["name"], "run_started_at": stamp,
                       "source_run_conclusion": run.get("conclusion") or "unknown",
                       **{k: product.get(k) or "NA" for k in ("brand", "model", "category")}})
    return result


def write_csv(path, rows, columns):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def seed_from_github(repo, branch, workflow):
    candidates = pages(repo, f"actions/workflows/{workflow}/runs?branch={branch}&status=success&per_page=100", "workflow_runs")
    for run in candidates:
        artifacts = pages(repo, f"actions/runs/{run['id']}/artifacts?per_page=100", "artifacts")
        matching = [a for a in artifacts if a["name"] == "combined-snapshots" and not a["expired"]]
        if matching:
            archive = api(repo, f"actions/artifacts/{matching[0]['id']}/zip")
            snapshots = read_csv_bytes(csv_member(archive, "combined_snapshots.csv"))
            manifest = json.loads(csv_member(archive, "snapshot_manifest.json"))
            return snapshots, manifest
    return [], {"artifacts": []}


def collect(repo, output, products_path, branch="main", seed_workflow="combined-snapshots.yml",
            seed_dir=None, required_run=None, no_seed=False):
    products = {r["product_id"]: r for r in read_csv_bytes(products_path.read_bytes())}
    if seed_dir:
        rows = read_csv_bytes((seed_dir / "combined_snapshots.csv").read_bytes())
        manifest = json.loads((seed_dir / "snapshot_manifest.json").read_text(encoding="utf-8"))
    elif no_seed:
        rows, manifest = [], {"artifacts": []}
    else:
        rows, manifest = seed_from_github(repo, branch, seed_workflow)
    if manifest.get("branch", branch) != branch:
        raise ValueError("Seed belongs to a different branch")
    entries = {str(a["id"]): a for a in manifest["artifacts"]}
    # List every completed run, including failures with useful partial artifacts.
    runs = pages(repo, f"actions/workflows/scrape.yml/runs?branch={branch}&status=completed&per_page=100", "workflow_runs")
    for run in sorted(runs, key=lambda r: r["created_at"]):
        for artifact in pages(repo, f"actions/runs/{run['id']}/artifacts?per_page=100", "artifacts"):
            match = ARTIFACT_RE.fullmatch(artifact["name"])
            if not match:
                continue
            aid = str(artifact["id"])
            if aid in entries and entries[aid].get("state") == "included":
                continue
            entry = {"id": artifact["id"], "run_id": run["id"], "name": artifact["name"]}
            if artifact["expired"]:
                entries[aid] = {**entry, "state": "expired_unavailable"}
                continue
            # Production collection period; omit pre-period smoke tests.
            if not "2026-10-19" <= match[2][:10] <= "2026-11-25":
                entries[aid] = {**entry, "state": "outside_collection_period"}
                continue
            archive = api(repo, f"actions/artifacts/{artifact['id']}/zip")
            data = csv_member(archive, artifact["name"] + ".csv")
            # Historical test-table dispatches must not become production observations.
            source_products = json.loads(api(repo, f"contents/products/products.csv?ref={run['head_sha']}"))
            source_table = read_csv_bytes(base64.b64decode(source_products["content"]))
            parsed = parse_snapshot(data, artifact, run, {p["product_id"]: p for p in source_table})
            expected = {p["product_id"] for p in source_table
                        if p.get(match[1] + "_url", "").strip() not in ("", "NA")}
            observed = {r["product_id"] for r in parsed}
            if observed != expected:
                entries[aid] = {**entry, "state": "product_set_mismatch", "rows": len(parsed),
                                "missing": sorted(expected - observed), "unexpected": sorted(observed - expected)}
                continue
            rows.extend(parsed)
            entries[aid] = {**entry, "state": "included", "rows": len(parsed)}
            print(f"Included {artifact['name']}: {len(parsed)} rows", flush=True)
    # Reruns replace a platform's earlier artifact, not create duplicate observations.
    latest = {}
    for row in rows:
        group = (row["source_run_id"], row["platform"])
        latest[group] = max(latest.get(group, 0), int(row["source_artifact_id"]))
    rows = [r for r in rows if int(r["source_artifact_id"]) == latest[(r["source_run_id"], r["platform"])]]
    unique = {}
    for row in rows:
        key = (row["source_run_id"], row["platform"], row["product_id"])
        if key in unique and row != unique[key]:
            raise ValueError(f"Conflicting observations for {key}")
        # Refresh descriptive metadata, never overwrite recorded price fields.
        row.update({k: products.get(row["product_id"], {}).get(k) or row.get(k) or "NA"
                    for k in ("brand", "model", "category")})
        unique[key] = row
    rows = sorted(unique.values(), key=lambda r: (r["date"], r["source_run_id"], r["platform"], r["product_id"]))
    if not rows:
        raise ValueError("No production snapshots found")
    if required_run and not any(r["source_run_id"] == str(required_run) for r in rows):
        raise ValueError(f"Triggering scrape {required_run} produced no usable production CSVs")
    counts = Counter((r["source_run_id"], r["platform"]) for r in rows)
    summary = []
    for run_id in sorted({r["source_run_id"] for r in rows}, key=int):
        members = [r for r in rows if r["source_run_id"] == run_id]
        summary.append({"source_run_id": run_id, "date": min(r["date"] for r in members),
                        "momo_rows": counts[(run_id, "momo")], "pchome_rows": counts[(run_id, "pchome")],
                        "pair_complete": str(all(counts[(run_id, p)] > 0 for p in ("momo", "pchome"))).upper(),
                        "ok_rows": sum(r["fetch_status"] == "ok" for r in members)})
    write_csv(output / "combined_snapshots.csv", rows, SNAPSHOT_COLUMNS + META_COLUMNS)
    write_csv(output / "snapshot_runs.csv", summary,
              ["source_run_id", "date", "momo_rows", "pchome_rows", "pair_complete", "ok_rows"])
    for run_id in {r["source_run_id"] for r in rows}:
        write_csv(output / "runs" / f"combined_{run_id}.csv",
                  [r for r in rows if r["source_run_id"] == run_id], SNAPSHOT_COLUMNS + META_COLUMNS)
    manifest = {"schema_version": 1, "branch": branch, "repository": repo,
                "generated_at": datetime.now(timezone.utc).isoformat(), "rows": len(rows),
                "artifacts": sorted(entries.values(), key=lambda a: int(a["id"]))}
    (output / "snapshot_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Combined {len(rows)} rows from {len(summary)} scraping runs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--output", type=Path, default=Path("output/combined"))
    parser.add_argument("--products", type=Path, default=Path("products/products.csv"))
    parser.add_argument("--branch", default="main")
    parser.add_argument("--seed-workflow", default="combined-snapshots.yml")
    parser.add_argument("--seed-dir", type=Path)
    parser.add_argument("--required-run", type=int)
    parser.add_argument("--no-seed", action="store_true")
    args = parser.parse_args()
    collect(args.repo, args.output, args.products, args.branch, args.seed_workflow,
            args.seed_dir, args.required_run, args.no_seed)
