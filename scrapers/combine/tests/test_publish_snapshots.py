import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from collect_snapshots import META_COLUMNS, SNAPSHOT_COLUMNS
from publish_snapshots import COLUMNS, publish


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.combined = root / "combined_snapshots.csv"
        self.data = root / "data"
        self.data.mkdir()
        self.products = root / "products.csv"
        self.products.write_text("product_id,brand\n3C-001,Test\n", encoding="utf-8")
        self.target = self.data / "source" / "snapshots.csv"

    def row(self, run, product, date="2026-10-25"):
        row = dict.fromkeys(SNAPSHOT_COLUMNS + META_COLUMNS, "NA")
        row.update(date=date, platform="momo", product_id=product, fetch_status="ok", sale_price="100",
                   source_run_id=run, source_artifact_id="9", brand="Test")
        return row

    def write_combined(self, rows):
        with self.combined.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=SNAPSHOT_COLUMNS + META_COLUMNS)
            writer.writeheader()
            writer.writerows(rows)

    def published(self):
        with self.target.open(encoding="utf-8", newline="") as handle:
            return list(csv.DictReader(handle))

    def test_keeps_spec_columns_plus_run_id_sorted_with_lf(self):
        self.write_combined([self.row("20", "3C-002", "2026-10-26"), self.row("9", "3C-001")])
        publish(self.combined, self.data, self.products)
        rows = self.published()
        self.assertEqual(list(rows[0]), COLUMNS)
        self.assertEqual([r["run_id"] for r in rows], ["9", "20"])
        self.assertNotIn(b"\r", self.target.read_bytes())
        self.assertEqual((self.data / "products.csv").read_bytes(), self.products.read_bytes())

    def test_refuses_to_drop_published_observations(self):
        self.write_combined([self.row("1", "3C-001"), self.row("2", "3C-001")])
        publish(self.combined, self.data, self.products)
        before = self.target.read_bytes()
        self.write_combined([self.row("2", "3C-001")])
        with self.assertRaisesRegex(ValueError, "Refusing to drop"):
            publish(self.combined, self.data, self.products)
        self.assertEqual(self.target.read_bytes(), before)

    def test_rejects_duplicate_observations(self):
        self.write_combined([self.row("1", "3C-001"), self.row("1", "3C-001")])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            publish(self.combined, self.data, self.products)


if __name__ == "__main__":
    unittest.main()
