"""Download a specific combined dataset, or find the latest non-empty successful build."""
import argparse
import json
from pathlib import Path
from collect_snapshots import api, csv_member, pages


def download(repo, output, run_id=None):
    runs = [{"id": run_id}] if run_id else pages(
        repo, "actions/workflows/combined-snapshots.yml/runs?branch=main&status=success&per_page=100", "workflow_runs")
    for run in runs:
        artifacts = pages(repo, f"actions/runs/{run['id']}/artifacts?per_page=100", "artifacts")
        for artifact in artifacts:
            if artifact["name"] != "combined-snapshots" or artifact["expired"]:
                continue
            archive = api(repo, f"actions/artifacts/{artifact['id']}/zip")
            output.mkdir(parents=True, exist_ok=True)
            for name in ("combined_snapshots.csv", "snapshot_manifest.json", "snapshot_runs.csv"):
                (output / name).write_bytes(csv_member(archive, name))
            # Identify the precise cumulative build used by the analysis.
            (output / "upstream.json").write_text(json.dumps({"run_id": run["id"],
                "artifact_id": artifact["id"]}, indent=2) + "\n", encoding="utf-8")
            print(f"Downloaded combined snapshots from run {run['id']}")
            return True
    return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-id", type=int)
    parser.add_argument("--output", type=Path, default=Path("output/combined"))
    args = parser.parse_args()
    found = download(args.repo, args.output, args.run_id)
    # Use a non-error sentinel so skipped backups do not create failed builds.
    import os
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
            handle.write(f"found={str(found).lower()}\n")
    if not found:
        print("No combined artifact yet; nothing to analyse.")
