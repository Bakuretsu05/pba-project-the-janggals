import csv
import io
import sys
import unittest
import zipfile
import tempfile
import json
import base64
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from collect_snapshots import SNAPSHOT_COLUMNS, collect, csv_member, parse_snapshot


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.row = dict.fromkeys(SNAPSHOT_COLUMNS, "NA")
        self.row.update(date="2026-10-25", scraped_at="2026-10-25 15:08:00",
                        product_id="3C-001", platform="momo", sale_price="100", fetch_status="ok")
        self.artifact = {"id": 123, "name": "momo_2026-10-25_1508"}
        self.run = {"id": 456, "run_attempt": 1, "html_url": "https://github.com/example/run/456",
                    "head_sha": "abc", "conclusion": "success", "created_at": "2026-10-25T07:07:00Z"}

    def encoded(self, rows):
        buffer = io.StringIO()
        writer = csv.DictWriter(buffer, fieldnames=SNAPSHOT_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
        return buffer.getvalue().encode("utf-8-sig")

    def test_missing_reference_preserved_with_provenance(self):
        rows = parse_snapshot(self.encoded([self.row]), self.artifact, self.run,
                              {"3C-001": {"category": "3C"}})
        self.assertEqual(rows[0]["original_price"], "NA")
        self.assertEqual(rows[0]["category"], "3C")
        self.assertEqual(rows[0]["source_run_id"], "456")

    def test_duplicate_product_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            parse_snapshot(self.encoded([self.row, self.row]), self.artifact, self.run, {})

    def test_wrong_platform_rejected(self):
        self.row["platform"] = "pchome"
        with self.assertRaisesRegex(ValueError, "disagrees"):
            parse_snapshot(self.encoded([self.row]), self.artifact, self.run, {})

    def test_csv_only_read_even_with_unsafe_zip_member(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("../../untrusted.R", "do not run")
            archive.writestr("output/momo.csv", self.encoded([self.row]))
        self.assertEqual(csv_member(buffer.getvalue(), "momo.csv"), self.encoded([self.row]))

    def test_ambiguous_csv_rejected(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("a/momo.csv", "a")
            archive.writestr("b/momo.csv", "b")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            csv_member(buffer.getvalue(), "momo.csv")

    def test_backfill_then_seed_is_idempotent_and_survives_raw_expiry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = root / "products.csv"
            products.write_text("product_id,brand,model,category,momo_url,pchome_url\n"
                                "3C-001,test,model,3C,https://momo,https://pchome\n", encoding="utf-8")
            source = json.dumps({"content": base64.b64encode(products.read_bytes()).decode()}).encode()
            archive = io.BytesIO()
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("output/" + self.artifact["name"] + ".csv", self.encoded([self.row]))
            def fake_pages(repo, endpoint, key):
                return [self.run] if key == "workflow_runs" else [{**self.artifact, "expired": False}]
            def fake_api(repo, endpoint, paginate=False):
                return source if endpoint.startswith("contents/") else archive.getvalue()
            out = root / "out"
            with patch("collect_snapshots.pages", side_effect=fake_pages), patch("collect_snapshots.api", side_effect=fake_api):
                collect("test/repo", out, products, no_seed=True)
            before = (out / "combined_snapshots.csv").read_bytes()
            def expired_pages(repo, endpoint, key):
                return [self.run] if key == "workflow_runs" else [{**self.artifact, "expired": True}]
            with patch("collect_snapshots.pages", side_effect=expired_pages), patch("collect_snapshots.api") as network:
                collect("test/repo", out, products, seed_dir=out)
                network.assert_not_called()
            self.assertEqual(before, (out / "combined_snapshots.csv").read_bytes())
            manifest = json.loads((out / "snapshot_manifest.json").read_text())
            self.assertEqual(manifest["rows"], 1)
            self.assertEqual(manifest["artifacts"][0]["state"], "included")


if __name__ == "__main__":
    unittest.main()
