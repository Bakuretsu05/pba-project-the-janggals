"""Build the analysis files in data/ from the archived scrapes.

Inputs:  data/source/snapshots.csv (every scrape, untouched) and data/products.csv.
Outputs: data/scrapes.csv            one row per listing (platform x product) per scrape run,
                                      successful pages of current listings only
         data/grids/<platform>_price_grid.csv
                                      one row per product, one column per date, 15:07 sale_price
         the status block in data/README.md

Nothing here is an analysis choice: no benchmarks, no discount percentages. The only
derived prices are lowest_shown_price (the lower of two prices the page showed) and
single_item_price (a PChome "any one item" 折 offer applied to sale_price), both
documented in data/README.md. Standard library only. Run from the repository root.
"""
import argparse
import csv
import io
import math
import re
from datetime import date, datetime, timedelta
from pathlib import Path

COLUMNS = [
    "date", "slot", "run_started_at", "platform", "product_id", "brand", "model", "category",
    "sale_price", "original_price", "extra_price", "extra_price_label",
    "lowest_shown_price", "single_item_price", "price_note", "promo_tag", "coupon_note",
]
PLATFORMS = ("momo", "pchome")
OFF_SCHEDULE = "off-schedule"

# Spec section 9: one run a day at 15:07 Taiwan time, plus 18:07 and 23:07 on Nov 10-12.
DAILY_SLOTS = ("15:07",)
EXTRA_SLOT_DAYS = {date(2026, 11, 10), date(2026, 11, 11), date(2026, 11, 12)}
EXTRA_SLOTS = ("18:07", "23:07")
# A run belongs to a slot if it started between 10 minutes before and 60 minutes after it.
# Later than that and it saw different prices (a 23:07 run at 06:13 the next morning saw
# post-Double-11 prices), so it is labelled off-schedule under its own start date.
EARLY = timedelta(minutes=10)
LATE = timedelta(minutes=60)
# The two first runs started hours late, before the outside timer existed, and are the
# 15:07 runs of their day (spec section 9, "late first runs").
LATE_SLOT_RUNS = {"39269783552": ("2026-10-19", "15:07"), "39423862445": ("2026-10-20", "15:07")}

# "任選1件享95折" / "滿1件享9折": any single item gets the 折, so it is the price paid.
SINGLE_ITEM_OFFER = re.compile(r"(?:任選|滿)1件享(\d{1,2})折")
UNLINKED_NOTE = "crossed-out price equals sale_price and no conditional price was linked; a discount may be missing"

STATUS = re.compile(r"(<!-- status:start -->\n).*?(<!-- status:end -->)", re.S)


def read(path):
    return list(csv.DictReader(io.StringIO(Path(path).read_bytes().decode("utf-8-sig"))))


def write(path, rows, columns):
    """UTF-8 with a BOM (so Excel shows the Chinese text), LF line endings, NA for missing."""
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=columns, lineterminator="\n")
    writer.writeheader()
    writer.writerows({c: ("NA" if r.get(c) is None else r[c]) for c in columns} for r in rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(buffer.getvalue().encode("utf-8-sig"))


def number(value):
    return None if value in ("", "NA", None) else int(value)


def listing_ids(products):
    """(platform, product_id) -> the platform's item ID in the current product table."""
    ids = {}
    for p in products:
        momo = re.search(r"[?&]i_code=(\w+)", p.get("momo_url") or "")
        pchome = re.search(r"/prod/([\w-]+)", p.get("pchome_url") or "")
        if momo:
            ids[("momo", p["product_id"])] = momo[1]
        if pchome:
            ids[("pchome", p["product_id"])] = pchome[1]
    return ids


def scheduled_slots(day):
    slots = DAILY_SLOTS + (EXTRA_SLOTS if day in EXTRA_SLOT_DAYS else ())
    return [datetime.combine(day, datetime.strptime(s, "%H:%M").time()) for s in slots]


def assign_slots(snapshots):
    """run_id -> (date, slot, run_started_at). Each scheduled slot goes to at most one run."""
    starts, dates = {}, {}
    for row in snapshots:
        run = row["run_id"]
        dates.setdefault(run, row["date"])
        if row["scraped_at"] not in ("", "NA"):
            starts[run] = min(starts.get(run, row["scraped_at"]), row["scraped_at"])
    runs = sorted(dates, key=lambda r: (starts.get(r, dates[r] + " 99"), r))
    taken, result = set(), {}
    for run in runs:
        started = starts.get(run)
        label = (dates[run], OFF_SCHEDULE)
        if run in LATE_SLOT_RUNS:
            label = LATE_SLOT_RUNS[run]
        elif started:
            moment = datetime.strptime(started, "%Y-%m-%d %H:%M:%S")
            for day in (moment.date() - timedelta(days=1), moment.date(), moment.date() + timedelta(days=1)):
                for slot in scheduled_slots(day):
                    if slot - EARLY <= moment < slot + LATE:
                        label = (slot.date().isoformat(), slot.strftime("%H:%M"))
        if label[1] != OFF_SCHEDULE and label in taken:
            label = (dates[run], OFF_SCHEDULE)  # a second run of a slot (e.g. a manual rerun)
        taken.add(label)
        result[run] = (*label, started)
    return result


def single_item_price(row, sale):
    """PChome only: momo already shows its 折後價 as extra_price. Rounded down, as PChome does."""
    if row["platform"] != "pchome":
        return None, None
    rates = [int(m) / (10 if len(m) == 1 else 100)
             for m in SINGLE_ITEM_OFFER.findall(f"{row['promo_tag']} {row['coupon_note']}")]
    if not rates:
        return None, None
    rate = min(rates)
    return math.floor(sale * rate + 1e-9), f"single_item_price is sale_price x {rate:g} from the offer text"


def build_scrapes(snapshots, products):
    info = {p["product_id"]: p for p in products}
    ids = listing_ids(products)
    slots = assign_slots(snapshots)
    rows = []
    for row in snapshots:
        key = (row["platform"], row["product_id"])
        # Successful pages of the listings in the current product table only. This also drops
        # the first run's listings that later left the table, or were replaced by another item.
        if row["fetch_status"] != "ok" or ids.get(key) != row["platform_item_id"]:
            continue
        sale, original, extra = (number(row[c]) for c in ("sale_price", "original_price", "extra_price"))
        if sale is None or sale <= 0:
            raise ValueError(f"ok row without a sale_price: run {row['run_id']} {key}")
        single, note = single_item_price(row, sale)
        if note is None and row["platform"] == "pchome" and original == sale and extra is None:
            note = UNLINKED_NOTE
        day, slot, started = slots[row["run_id"]]
        product = info[row["product_id"]]
        rows.append({
            "date": day, "slot": slot, "run_started_at": started,
            "platform": row["platform"], "product_id": row["product_id"],
            "brand": product["brand"], "model": product["model"], "category": product["category"],
            "sale_price": sale, "original_price": original, "extra_price": extra,
            "extra_price_label": None if extra is None else row["extra_price_label"],
            "lowest_shown_price": sale if extra is None else min(sale, extra),
            "single_item_price": single, "price_note": note,
            "promo_tag": number_or_text(row["promo_tag"]), "coupon_note": number_or_text(row["coupon_note"]),
        })
    rows.sort(key=lambda r: (r["run_started_at"] or "", r["date"], r["platform"], r["product_id"]))
    keys = [(r["date"], r["slot"], r["run_started_at"], r["platform"], r["product_id"]) for r in rows]
    if len(set(keys)) != len(keys):
        raise ValueError("Duplicate listing within one scrape run")
    return rows


def number_or_text(value):
    return None if value in ("", "NA") else value


def build_grid(rows, products, platform):
    """One row per product listed on the platform; one column per date with a 15:07 run."""
    prices = {(r["product_id"], r["date"]): r["sale_price"]
              for r in rows if r["platform"] == platform and r["slot"] == "15:07"}
    dates = sorted({d for _, d in prices})
    grid = []
    for p in sorted(products, key=lambda p: p["product_id"]):
        if p.get(f"{platform}_url"):
            grid.append({"product_id": p["product_id"], "brand": p["brand"], "model": p["model"],
                         "category": p["category"], **{d: prices.get((p["product_id"], d)) for d in dates}})
    return grid, ["product_id", "brand", "model", "category"] + dates


def update_status(readme, rows):
    if not readme.exists():
        return
    runs = {(r["date"], r["slot"], r["run_started_at"]) for r in rows}
    off = sum(1 for _, slot, _ in runs if slot == OFF_SCHEDULE)
    last = max((r["date"], r["slot"]) for r in rows if r["slot"] != OFF_SCHEDULE)
    status = (f"- `scrapes.csv`: **{len(rows):,} rows** from **{len(runs)} scrape runs** "
              f"({off} off-schedule), latest scheduled run **{last[0]} {last[1]}** (Taiwan time)\n")
    text = readme.read_text(encoding="utf-8")
    updated = STATUS.sub(lambda m: m[1] + status + m[2], text)
    if updated == text and status not in text:
        raise ValueError("data/README.md lacks the status markers")
    readme.write_text(updated, encoding="utf-8", newline="\n")


def build(data_dir):
    products = read(data_dir / "products.csv")
    rows = build_scrapes(read(data_dir / "source" / "snapshots.csv"), products)
    if not rows:
        raise ValueError("No successful scrapes to publish")
    write(data_dir / "scrapes.csv", rows, COLUMNS)
    for platform in PLATFORMS:
        grid, columns = build_grid(rows, products, platform)
        write(data_dir / "grids" / f"{platform}_price_grid.csv", grid, columns)
    update_status(data_dir / "README.md", rows)
    print(f"Wrote data/scrapes.csv ({len(rows)} rows) and data/grids/")
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    build(parser.parse_args().data_dir)
