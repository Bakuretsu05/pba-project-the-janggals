"""Record input checksums and the analysis code revision beside derived data."""
import hashlib
import json
import subprocess
from pathlib import Path
from datetime import datetime, timezone

inputs = [Path("products/products.csv"), Path("biggo/price_changes.csv"),
          Path("output/combined/combined_snapshots.csv"), Path("analysis/build_analysis.R")]
inputs += sorted(Path("analysis/config").glob("*.csv"))
metadata = {"generated_at": datetime.now(timezone.utc).isoformat(),
            "code_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
            "sha256": {p.as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}}
Path("output/analysis/build_manifest.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
