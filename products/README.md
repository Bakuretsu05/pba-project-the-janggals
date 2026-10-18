# Products

Owners: **Alicia, Audrey** · Due **Saturday, Oct 17**

## The task

Pick about **100 products** that we will track on three Taiwanese shopping sites (momo,
PChome, Coupang) until Double 11, and list them in one file:

**`products/products.csv`** (this folder)

The file is already there with its header line filled in: add your products below it. The
scrapers read this file automatically, so its format has to match the description below
exactly.

## File format

- A CSV file, saved as **UTF-8** (product names may contain Chinese).
- The first line is exactly this header:

```
product_id,brand,model,category,momo_url,pchome_url,coupang_url,biggo_url_momo,biggo_url_pchome,biggo_url_coupang
```

- Then one line per product. An empty cell means "not sold on that site".

| Column | What to write | Example |
|---|---|---|
| `product_id` | Category code, a hyphen, and a 3-digit number, counting up within each category. Each one is used once | `3C-001`, `3C-002`, `BEAU-001` |
| `brand` | The brand | `Apple` |
| `model` | The exact product, including size, colour or pack count | `AirPods 4 (ANC)` |
| `category` | One of the five codes below | `3C` |
| `momo_url` | Link to the product on momo | `https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=...` |
| `pchome_url` | Link to the product on PChome | `https://24h.pchome.com.tw/prod/...` |
| `coupang_url` | Link to the product on Coupang. Must contain `itemId=` | |
| `biggo_url_momo` | Link to BigGo's price-history page for the momo listing | |
| `biggo_url_pchome` | Same, for the PChome listing | |
| `biggo_url_coupang` | Same, for the Coupang listing | |

Category codes:

| Code | Category |
|---|---|
| `3C` | Electronics |
| `APPL` | Small appliances |
| `BEAU` | Beauty |
| `FOOD` | Snacks and drinks |
| `HOME` | Home and daily goods |

## Which products count

A product goes on the list only if **all four** are true:

1. **Sold on at least 2 of the 3 sites**, as the exact same item on each: same size, colour and
   pack count.
2. **Sold by the site itself**, not by another seller on the site. How to tell:
   - momo: the link is on `momoshop.com.tw`. Links on `momomall.com.tw` (momo摩天商城) are
     other sellers.
   - PChome: the link is on `24h.pchome.com.tw`. Links on `mall.pchome.com.tw` (商店街) are
     other sellers.
   - Coupang: the listing shows the 火箭速配 (Rocket) badge.
3. **BigGo has its price history back to October 2025.** Search the product on
   [biggo.com.tw](https://biggo.com.tw), open the listing for each site, and check that the
   price chart reaches October 2025.
4. **Students would actually buy it.**

Aim for about **20 products per category**.

## Before handing it in

- [ ] The header line matches the one above exactly.
- [ ] Every `product_id` is different and follows the pattern (`3C-001`).
- [ ] Every `category` is one of the five codes.
- [ ] Every product has a link for at least 2 of momo, PChome and Coupang.
- [ ] Every product's links point to the same item, sold by the site itself.
- [ ] Every link you filled in has a matching BigGo link.
- [ ] The file is saved as UTF-8: open it again and check that any Chinese text reads correctly.
