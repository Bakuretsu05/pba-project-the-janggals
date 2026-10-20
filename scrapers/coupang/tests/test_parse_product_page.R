# Tests of parse_product_page() on markup copied from real Coupang pages (fixtures/). Expected
# values are what those pages showed in a browser on 2026-10-15. No sold-out page has been seen
# yet: sold_out.html is the AirPods page with its JSON-LD availability set to OutOfStock. Run from
# the project root:
#
#   Rscript scrapers/coupang/tests/test_parse_product_page.R

source("scrapers/coupang/scrape_coupang.R")
source("scrapers/coupang/tests/helpers.R")

test("a plain discount with a card price (AirPods 4)", {
  page <- parse_product_page(fixture_page("airpods"))
  f <- page$fields

  expect_equal(page$found, TRUE)
  expect_equal(f$original_price, 4490L)
  expect_equal(f$sale_price, 3590L)
  expect_equal(f$extra_price, 3410L)
  expect_equal(f$extra_price_label, "王道卡 特惠價")
  expect_equal(f$shown_discount_pct, NA_real_)
  expect_equal(f$promo_tag, "8折")
  expect_equal(f$coupon_note, paste("王道卡 特惠價 $3,410 (滿 $20,000 再省 $1,020)",
                                    "國泰世華銀行 最高 3.3%小樹點", "星展銀行 最高 $100刷卡金", sep = " | "))
  expect_equal(f$seller_type, "platform")
  expect_equal(f$in_stock, TRUE)
})

test("a first-purchase headline is the extra price; the sale price is the price without it", {
  page <- parse_product_page(fixture_page("first_purchase"))
  f <- page$fields

  expect_equal(page$found, TRUE)
  expect_equal(f$original_price, 199L)
  expect_equal(f$sale_price, 199L)
  expect_equal(f$extra_price, 1L)
  expect_equal(f$extra_price_label, "首購折扣價")
  expect_equal(f$promo_tag, "0.1折")
  expect_equal(f$coupon_note, "$198 首購折扣價 · 折扣剩下9小時")
})

test("a first-purchase headline whose figures do not add up is not read (parse_failure)", {
  html <- sub('"price":"199"', '"price":"250"', fixture_page("first_purchase"), fixed = TRUE)
  page <- parse_product_page(html)

  expect_equal(page$found, FALSE)
  expect_true(grepl("首購折扣價", page$note))
})

test("a time-limited discount is the extra price; its line's struck price is the sale price", {
  page <- parse_product_page(fixture_page("timed_discount"))
  f <- page$fields

  expect_equal(page$found, TRUE)
  expect_equal(f$original_price, 590L)
  expect_equal(f$sale_price, 490L)
  expect_equal(f$extra_price, 425L)
  expect_equal(f$extra_price_label, "折扣後價格")
  expect_equal(f$promo_tag, "73折")
  expect_equal(f$coupon_note, "$65 折扣後價格 · 折扣剩下8小時 $490")
})

test("a time-limited discount with no price on its line takes the struck price as sale price", {
  html <- sub("<div translate=\"no\" class=\"twc-text-[14px] twc-line-through twc-text-bluegray-600\">$490</div>",
              "", fixture_page("timed_discount"), fixed = TRUE)
  html <- sub(">$65<", ">$165<", html, fixed = TRUE)
  f <- parse_product_page(html)$fields

  expect_equal(f$original_price, 590L)
  expect_equal(f$sale_price, 590L)
  expect_equal(f$extra_price, 425L)
})

test("a third-party seller is marketplace", {
  page <- parse_product_page(fixture_page("marketplace"))
  f <- page$fields

  expect_equal(f$original_price, 700L)
  expect_equal(f$sale_price, 490L)
  expect_equal(f$extra_price, NA_integer_)
  expect_equal(f$promo_tag, "7折")
  expect_equal(f$seller_type, "marketplace")
})

test("a sold-out item is found, with in_stock FALSE and the prices shown", {
  page <- parse_product_page(fixture_page("sold_out"))

  expect_equal(page$found, TRUE)
  expect_equal(page$fields$in_stock, FALSE)
  expect_equal(page$fields$sale_price, 3590L)
})

test("Coupang's 找不到商品 page is not found, with the reason", {
  page <- parse_product_page(fixture_page("not_found"))

  expect_equal(page$found, FALSE)
  expect_true(grepl("找不到商品", page$note))
})

test("Akamai's and Coupang's refusal pages are block pages; a product page is not", {
  expect_true(is_block_page(fixture_page("access_denied")))
  expect_true(is_block_page('<div id="error403">你沒有權限存取此頁面</div>'))
  expect_true(is_block_page('<div id="sec-if-cpt-container" role="main">'))
  expect_true(!is_block_page(fixture_page("airpods")))
})

report()
