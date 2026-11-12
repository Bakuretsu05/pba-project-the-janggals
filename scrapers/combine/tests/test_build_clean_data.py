import csv
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_clean_data import COLUMNS, UNLINKED_NOTE, assign_slots, build
from publish_snapshots import COLUMNS as SNAPSHOT_COLUMNS

PRODUCTS = [
    {"product_id": "3C-006", "brand": "Acme", "model": "Cable, 1m", "category": "3C",
     "momo_url": "https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=111",
     "pchome_url": "https://24h.pchome.com.tw/prod/DYAJ-A900", "coupang_url": ""},
    {"product_id": "BEAU-031", "brand": "理膚寶水", "model": "Lotion", "category": "BEAU",
     "momo_url": "https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=222", "pchome_url": "", "coupang_url": ""},
]


def snapshot(run, started, platform="momo", product="3C-006", item="111", **values):
    row = dict.fromkeys(SNAPSHOT_COLUMNS, "NA")
    row.update(date=started[:10], scraped_at=started, platform=platform, product_id=product,
               platform_item_id=item, sale_price="590", fetch_status="ok", run_id=run, source="scraper")
    row.update(values)
    return row


def write_csv(path, rows, columns):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


class SlotTests(unittest.TestCase):
    def slots(self, *starts):
        return assign_slots([snapshot(str(i), s) for i, s in enumerate(starts)])

    def test_on_time_runs_get_their_slot(self):
        result = self.slots("2026-10-22 15:08:57", "2026-11-10 18:08:35", "2026-11-10 23:08:19")
        self.assertEqual([v[:2] for v in result.values()],
                         [("2026-10-22", "15:07"), ("2026-11-10", "18:07"), ("2026-11-10", "23:07")])

    def test_evening_slots_exist_only_on_nov_10_to_12(self):
        self.assertEqual(self.slots("2026-11-09 18:08:00")["0"][:2], ("2026-11-09", "off-schedule"))

    def test_a_run_just_after_midnight_belongs_to_the_23_07_slot_before(self):
        self.assertEqual(self.slots("2026-11-13 00:05:00")["0"][:2], ("2026-11-12", "23:07"))

    def test_a_run_hours_late_is_off_schedule_under_its_own_date(self):
        # The Nov 11 23:07 backup that started at 06:13 saw post-Double-11 prices.
        self.assertEqual(self.slots("2026-11-12 06:13:36")["0"][:2], ("2026-11-12", "off-schedule"))
        self.assertEqual(self.slots("2026-10-21 01:26:08")["0"][:2], ("2026-10-21", "off-schedule"))

    def test_documented_late_first_runs_keep_their_15_07_slot(self):
        rows = [snapshot("39269783552", "2026-10-19 22:33:45"), snapshot("39423862445", "2026-10-20 20:40:27")]
        self.assertEqual([v[:2] for v in assign_slots(rows).values()],
                         [("2026-10-19", "15:07"), ("2026-10-20", "15:07")])

    def test_a_second_run_of_the_same_slot_is_off_schedule(self):
        result = self.slots("2026-10-22 15:08:00", "2026-10-22 15:40:00")
        self.assertEqual((result["0"][1], result["1"][1]), ("15:07", "off-schedule"))


class BuildTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.data = Path(temp.name) / "data"
        write_csv(self.data / "products.csv", PRODUCTS, list(PRODUCTS[0]))
        (self.data / "README.md").write_text("<!-- status:start -->\nold\n<!-- status:end -->\n", encoding="utf-8")

    def run_build(self, snapshots):
        write_csv(self.data / "source" / "snapshots.csv", snapshots, SNAPSHOT_COLUMNS)
        build(self.data)
        raw = (self.data / "scrapes.csv").read_bytes()
        return raw, {(r["platform"], r["product_id"], r["date"]): r
                     for r in csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))}

    def test_keeps_only_successful_pages_of_current_listings(self):
        _, rows = self.run_build([
            snapshot("1", "2026-10-22 15:08:00"),
            snapshot("1", "2026-10-22 15:08:05", product="BEAU-031", item="222", fetch_status="parse_failure",
                     sale_price="NA"),
            snapshot("1", "2026-10-22 15:08:09", product="3C-001", item="999"),   # left the product table
            snapshot("2", "2026-10-23 15:08:00", item="555"),                    # replaced by another item
        ])
        self.assertEqual(list(rows), [("momo", "3C-006", "2026-10-22")])

    def test_columns_encoding_and_product_details(self):
        raw, rows = self.run_build([snapshot("1", "2026-10-22 15:08:00", product="BEAU-031", item="222")])
        self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
        self.assertNotIn(b"\r", raw)
        row = rows[("momo", "BEAU-031", "2026-10-22")]
        self.assertEqual(list(row), COLUMNS)
        self.assertEqual((row["brand"], row["category"], row["slot"]), ("理膚寶水", "BEAU", "15:07"))
        self.assertEqual((row["extra_price"], row["single_item_price"], row["price_note"]), ("NA", "NA", "NA"))

    def test_lowest_shown_price_is_the_lower_of_sale_and_extra(self):
        _, rows = self.run_build([snapshot("1", "2026-10-22 15:08:00", extra_price="560",
                                           extra_price_label="限時折後價")])
        row = rows[("momo", "3C-006", "2026-10-22")]
        self.assertEqual((row["lowest_shown_price"], row["extra_price_label"]), ("560", "限時折後價"))

    def test_pchome_single_item_offer_is_applied_and_rounded_down(self):
        _, rows = self.run_build([snapshot("1", "2026-10-22 15:08:00", platform="pchome", item="DYAJ-A900",
                                           original_price="590",
                                           promo_tag="雙11大瘋殺 11/01 - 11/13 任選1件享95折 | 滿$2000折$150")])
        row = rows[("pchome", "3C-006", "2026-10-22")]
        self.assertEqual(row["single_item_price"], "560")  # 590 x 0.95 = 560.5; BigGo shows 560
        self.assertEqual(row["lowest_shown_price"], "590")  # the page itself showed no lower price
        self.assertIn("0.95", row["price_note"])

    def test_single_digit_zhe_and_money_off_offers(self):
        _, rows = self.run_build([
            snapshot("1", "2026-10-22 15:08:00", platform="pchome", item="DYAJ-A900", sale_price="1000",
                     promo_tag="食品指定品享9折 11/01 - 11/30 滿1件享9折"),
            snapshot("2", "2026-10-23 15:08:00", platform="pchome", item="DYAJ-A900", sale_price="1000",
                     original_price="1000", promo_tag="滿$2000折$150，最高折$500"),
        ])
        self.assertEqual(rows[("pchome", "3C-006", "2026-10-22")]["single_item_price"], "900")
        money_off = rows[("pchome", "3C-006", "2026-10-23")]
        self.assertEqual((money_off["single_item_price"], money_off["price_note"]), ("NA", UNLINKED_NOTE))

    def test_momo_offers_are_left_to_extra_price(self):
        _, rows = self.run_build([snapshot("1", "2026-10-22 15:08:00", promo_tag="任選1件享95折")])
        self.assertEqual(rows[("momo", "3C-006", "2026-10-22")]["single_item_price"], "NA")

    def test_grid_has_one_row_per_listed_product_and_15_07_prices_only(self):
        self.run_build([snapshot("1", "2026-11-10 15:08:00", sale_price="590"),
                        snapshot("2", "2026-11-10 18:08:00", sale_price="499")])
        grid = list(csv.reader(io.StringIO((self.data / "grids" / "momo_price_grid.csv").read_bytes().decode("utf-8-sig"))))
        self.assertEqual(grid[0], ["product_id", "brand", "model", "category", "2026-11-10"])
        self.assertEqual([r[0] for r in grid[1:]], ["3C-006", "BEAU-031"])
        self.assertEqual((grid[1][4], grid[2][4]), ("590", "NA"))
        self.assertEqual(grid[1][2], "Cable, 1m")
        pchome = (self.data / "grids" / "pchome_price_grid.csv").read_bytes().decode("utf-8-sig").splitlines()
        self.assertEqual(len(pchome), 2)  # header + 3C-006 (BEAU-031 has no PChome link)

    def test_readme_status(self):
        self.run_build([snapshot("1", "2026-11-10 15:08:00"), snapshot("2", "2026-11-12 06:13:00")])
        readme = (self.data / "README.md").read_text(encoding="utf-8")
        self.assertIn("**2 rows** from **2 scrape runs** (1 off-schedule), latest scheduled run **2026-11-10 15:07**", readme)
        self.assertNotIn("old", readme)


if __name__ == "__main__":
    unittest.main()
