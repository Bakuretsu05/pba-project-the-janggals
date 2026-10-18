# Product list: selection notes

Notes on `products.csv` (rebuilt 2026-10-18 to replace the search-page links in `Productss.csv`).

## What was checked

- Every link is a product page, not a search page: momo `i_code=`, PChome `/prod/<id>`, Coupang `itemId=`.
- Sold by the site itself: momo links are on `momoshop.com.tw` and PChome links on `24h.pchome.com.tw`. Every Coupang link had the 火箭速配 (Rocket) badge in search results on 2026-10-18.
- Same item on each site, matched by model number, size, colour and pack count from the listing titles.
- Every product is on at least 2 sites: 40 on all three, 60 on two.

## Still to check by hand: BigGo history

BigGo blocked automated lookups, so the rule "price history back to October 2025" is **not yet checked** for most listings. For each BigGo link: open it, find the listing on BigGo, open the price chart (價格歷史) and check it starts by October 2025. If it does not, remove that site's link and its BigGo link (the product must keep at least 2 sites). Seven listings were already checked and pass: momo 13521467, 8697108, 9372221, 12219772 and PChome DYAJD2-A900GAFRM, DYAJBS-A900GPCJK, DYAJG7-A900GQUUT.

The rows marked "may be newer than Oct 2025" below are the most likely to fail.

BigGo has no separate page per listing, so each BigGo column holds `https://biggo.com.tw/r/?i=<shop>&id=<id>`: unique per listing, and `<shop>-<id>` is the ID BigGo's price chart uses.

## Changes from the original list

| ID | Product | Sites | Note |
|---|---|---|---|
| 3C-001 | Apple AirPods 4 with Active Noise Cancellation (MXP93TA/A) | momo, Coupang | no PChome listing (only refurbished) |
| 3C-002 | Apple AirPods 4 (MXP63TA/A) | momo, Coupang | replaces AirPods Pro 3 (launched Sep 2025, BigGo history too short); no PChome listing |
| 3C-006 | Apple EarPods (USB-C) MYQY3 | momo, PChome, Coupang | replaces iPad A16 (all listings start 2026, too new for BigGo history) |
| 3C-007 | Logitech Pebble Mouse 2 M350s (graphite) | momo, PChome, Coupang | replaces MagSafe Charger 1 m (listings start Dec 2025) |
| 3C-008 | Anker A1664 10000mAh Qi2 magnetic power bank | momo, PChome, Coupang | was "PowerCore 10000" (not a current model) |
| 3C-009 | Anker A1636 5000mAh 30W 3-in-1 power bank (black) | PChome, Coupang | replaces Anker 735 (not sold); momo only has it in white/pink |
| 3C-010 | Samsung Portable SSD T7 1TB, Titan Gray (MU-PC1T0T/WW) | momo, PChome | both listings may be newer than Oct 2025 |
| 3C-011 | Logitech MX Master 3S Lite (graphite) | momo, PChome, Coupang | the full MX Master 3S is only sold as the B2B edition now; listings may be newer than Oct 2025 |
| 3C-014 | Logitech C270 HD webcam | momo, PChome, Coupang | replaces C920 (not on momo) |
| 3C-018 | Anker soundcore Liberty 4 NC earbuds | momo, PChome | replaces Space A40 (not sold) |
| 3C-019 | SanDisk Ultra microSDXC 128GB (100MB/s) | momo, PChome | replaces Samsung EVO Plus (momo only had a parallel import) |
| APPL-001 | Panasonic EH-NA9N-H nanoe hair dryer | momo, PChome | replaces Dyson HD15 (not sold) |
| APPL-002 | Panasonic EH-NA7M-H nanoe hair dryer (silver) | momo, PChome, Coupang | replaces EH-NA0J (not on PChome or Coupang) |
| APPL-003 | Panasonic EH-NE57-A ionity hair dryer (blue) | momo, PChome, Coupang | replaces EH-NA32 (only on momo) |
| APPL-004 | Philips NA221 4.2L air fryer (black) | momo, PChome | replaces HD9252 (not on momo) |
| APPL-005 | Philips NA110 3.2L air fryer | momo, PChome, Coupang | replaces HD9650 (not sold) |
| APPL-006 | Tefal Ultra air fryer 4.2L EY111B70 | momo, PChome, Coupang | replaces EY9428 (not sold); momo listing may be newer than Oct 2025 |
| APPL-007 | Panasonic F-Y20JH 10L dehumidifier | momo, PChome, Coupang | momo listing may be newer than Oct 2025 |
| APPL-009 | Xiaomi Smart Air Purifier 4 Lite (AC-M17-SC) | PChome, Coupang | momo only sells the mainland-China version |
| APPL-010 | Philips HD9389 1.5L stainless steel kettle | momo, PChome, Coupang | replaces HD9350 (not sold); PChome listing may be newer than Oct 2025 |
| APPL-012 | Xiaomi Robot Vacuum H40 | momo, PChome, Coupang | replaces Roborock Q8 Max (not sold) |
| APPL-013 | Panasonic NI-M300T steam iron (blue) | momo, PChome | replaces NI-WL30 (not sold) |
| APPL-014 | Panasonic ES-6510 rotary shaver | momo, PChome, Coupang | replaces ES-LV9 (not sold) |
| APPL-015 | Oral-B iO2 electric toothbrush | momo, PChome | replaces iO Series 4 (not sold) |
| APPL-016 | Philips Sonicare HX5191 electric toothbrush | momo, PChome | replaces HX3671 (not sold); listings may be newer than Oct 2025 |
| APPL-018 | SodaStream GAIA sparkling water maker (black) | momo, PChome | replaces Terra (not sold in Taiwan) |
| BEAU-001 | Anessa Perfect UV Sunscreen Skincare Milk NA 60ml | PChome, Coupang | no momo listing |
| BEAU-002 | Biore UV Aqua Rich Watery Essence 70g | momo, PChome, Coupang | was 50g (only sold as a limited edition) |
| BEAU-003 | La Roche-Posay Anthelios UVMune 400 Invisible Fluid 50ml | momo, PChome, Coupang | PChome listing may be newer than Oct 2025 |
| BEAU-004 | La Roche-Posay Cicaplast Baume B5+ 40ml | momo, PChome | listings may be newer than Oct 2025 |
| BEAU-005 | SK-II Facial Treatment Essence 230ml | momo, PChome | PChome sells the travel-retail version, momo the counter version |
| BEAU-007 | DR.WU Hyaluronic Acid Hydrating Toner 150ml (classic) x2 | momo, PChome, Coupang | replaces Lancome Genifique 50ml (only a new Pro version) |
| BEAU-008 | Cetaphil Gentle Skin Cleanser 591ml | momo, PChome | momo listing may be newer than Oct 2025 |
| BEAU-011 | CeraVe Moisturizing Cream 340g | momo, PChome | replaces Curel cream (only on momo); momo calls its listing a "限定組", check it is the plain 340g tub |
| BEAU-012 | Avene Thermal Spring Water 300ml x4 | momo, PChome, Coupang | was 300ml (single bottle not on PChome); 4-pack is on all three sites |
| BEAU-013 | Skin Aqua Mentholatum SKINAQUA sunscreen spray 90g (unscented) | momo, Coupang | was the 50g spray (only on PChome); check momo sells the unscented one |
| BEAU-014 | Neutrogena Hydro Boost Water Gel 50g | momo, Coupang | replaces Kiehl's Ultra Facial Cream (only on PChome); momo listing lets you choose gel/cream/night, track the gel |
| BEAU-017 | Bioderma Sensibio H2O micellar water 500ml x2 | momo, PChome | momo listing may be newer than Oct 2025 |
| BEAU-018 | Innisfree Green Tea Seed Hyaluronic Serum 80ml | momo, Coupang | no PChome listing |
| BEAU-019 | KISSME Heroine Make Micro Mascara EX 360 4.5g (black) | momo, Coupang | replaces Maybelline Sky High (only new limited editions); no PChome listing |
| FOOD-004 | Wei Lih Zha Jiang Mian 90g x5 | momo, PChome, Coupang | replaces Neoguri (not on momo) |
| FOOD-005 | Coca-Cola Coca-Cola Plus Fiber 330ml can x24 | momo, PChome, Coupang | replaces Dolce Gusto Latte Macchiato (only on momo) |
| FOOD-006 | Nespresso Original 50-capsule set (訂製咖啡時光) | momo, PChome | was Ispirazione Roma 10 capsules (not on PChome) |
| FOOD-007 | Starbucks by Nespresso capsules 10 x5 boxes | momo, PChome | PChome listing may be newer than Oct 2025 |
| FOOD-008 | Nescafe Gold Blend microground coffee 120g jar | PChome, Coupang | replaces Gold Blend 200g jar (not sold); momo only sells bundles |
| FOOD-012 | Evian Natural Mineral Water 500ml x24 | PChome, Coupang | no momo listing |
| FOOD-013 | Red Bull Energy Drink 250ml x24 | PChome, Coupang | no momo listing (momo only sells 3 cases) |
| FOOD-014 | Pringles Minis Original 19g x60 (2 boxes) | momo, PChome | was Original 110g (not on momo) |
| FOOD-015 | Oreo sandwich cookie snack pack | momo, PChome | check that the pack counts match |
| FOOD-016 | Pocari Sweat Ion Water 580ml x24 | momo, PChome, Coupang | replaces Ferrero Rocher T16 (only on momo) |
| FOOD-017 | Meiji Chocolate Kouka CACAO 72% 26 pieces | momo, PChome | replaces Hello Panda (not sold) |
| FOOD-019 | Haribo Goldbears share pack 200g | momo, PChome, Coupang | listings may be newer than Oct 2025 |
| FOOD-020 | Airwaves Super Cool Mint sugar-free gum 62g x10 | momo, PChome, Coupang | replaces Lotte Xylitol (not sold) |
| HOME-001 | Kleenex Cottony Soft facial tissue 100 sheets x12 | momo, PChome | momo listing may be newer than Oct 2025 |
| HOME-002 | May Flower Soft & Strong facial tissue 110 sheets x72 | momo, PChome, Coupang | replaces Breeze (PChome exclusive) |
| HOME-004 | Ariel Double Power liquid detergent refill 1100g x6 | momo, PChome | PChome listing may be newer than Oct 2025 |
| HOME-005 | Bear Brand Softener refill 1.75L/1.84L | momo, PChome | replaces Downy softener (not on momo) |
| HOME-006 | Bai Ge Anti-mite fabric softener refill 1800g | momo, PChome | replaces Comfort (not sold in Taiwan) |
| HOME-007 | Ariel Antibacterial liquid detergent refill 1.69kg (stain removal) | PChome, Coupang | replaces Dettol antiseptic (only on momo); PChome listing lets you choose the type, track 抗菌去漬 |
| HOME-008 | Febreze Antibacterial fabric refresher 370ml | momo, PChome | momo listing may be newer than Oct 2025 |
| HOME-014 | Dove Deeply Nourishing body wash 900g | momo, PChome | was 1000ml (not sold) |
| HOME-015 | Head & Shoulders anti-dandruff shampoo 680g | momo, PChome | was 750ml (not sold) |
| HOME-016 | Pantene shampoo 650g | momo, PChome | was 700ml (not sold) |
| HOME-017 | Paoshu Dishwashing liquid refill 800g x12 | momo, PChome | replaces Mama Lemon (not found) |
