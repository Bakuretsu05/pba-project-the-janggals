import csv
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publish_analysis import INPUTS, prepare


class PublishAnalysisTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.artifact = self.root / "artifact"
        self.artifact.mkdir()
        self.dest = self.root / "data"
        self.blobs = dict.fromkeys(INPUTS, b"fixture\n")
        self.blobs["products/products.csv"] = b"product_id\n3C-001\n"
        manifest = {"sha256": {k: hashlib.sha256(v).hexdigest() for k, v in self.blobs.items()}}
        (self.artifact / "build_manifest.json").write_text(json.dumps(manifest))
        self.rows = [{"product_id": "3C-001", "platform": platform, "year": str(year),
                      "analysis_as_of": "2026-10-30", "analysis_status": "incomplete",
                      "latest_snapshot_date": "2026-10-30" if year == 2026 else "NA"}
                     for platform in ("momo", "pchome") for year in (2025, 2026)]
        self.write_fixture()

    def tearDown(self):
        self.temp.cleanup()

    def write_fixture(self):
        with (self.artifact / "final_analysis.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(self.rows[0]))
            writer.writeheader()
            writer.writerows(self.rows)

    def prepare(self):
        with patch("publish_analysis.git_blob", side_effect=lambda root, name: self.blobs[name]):
            prepare(self.artifact, self.dest, self.root)

    def test_repeat_build_has_identical_files_and_preserves_other_data(self):
        self.dest.mkdir()
        other = self.dest / "existing.csv"
        other.write_text("preserve me")
        self.prepare()
        first = {p.name: p.read_bytes() for p in self.dest.iterdir()}
        self.prepare()
        self.assertEqual(first, {p.name: p.read_bytes() for p in self.dest.iterdir()})
        self.assertEqual(other.read_text(), "preserve me")
        self.assertIn("2026-10-30", (self.dest / "README.md").read_text())

    def test_changed_input_refuses_publication(self):
        self.blobs["biggo/price_changes.csv"] = b"new history"
        with self.assertRaisesRegex(ValueError, "Build input changed"):
            self.prepare()
        self.assertFalse(self.dest.exists())

    def test_older_build_cannot_replace_newer_table(self):
        self.prepare()
        before = (self.dest / "final_analysis.csv").read_bytes()
        for row in self.rows:
            row["analysis_as_of"] = "2026-10-29"
            row["latest_snapshot_date"] = "NA"
        self.write_fixture()
        with self.assertRaisesRegex(ValueError, "newer published"):
            self.prepare()
        self.assertEqual(before, (self.dest / "final_analysis.csv").read_bytes())

    def test_incomplete_or_duplicate_rows_are_rejected(self):
        self.rows[-1] = self.rows[0].copy()
        self.write_fixture()
        with self.assertRaisesRegex(ValueError, "duplicate or missing"):
            self.prepare()


if __name__ == "__main__":
    unittest.main()
