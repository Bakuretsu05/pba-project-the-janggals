# The Janggals: Milestone 3 (first visualization)
# Are Double 11 discounts real?
#
# Run this file from the analysis/ folder, so the data is at ../data/
# (same rule as analysis/README.md). The report milestone3_report.qmd
# uses exactly the same code.

library(tidyverse)

# ---- 1. Load the data ----------------------------------------------------

scrapes <- read_csv("../data/scrapes.csv", show_col_types = FALSE)

event_day <- as.Date("2026-11-11")

# One price per listing per day: keep only the scheduled 15:07 run
daily <- scrapes |>
  filter(slot == "15:07")

# Verify: one row per listing per day (this should print 0 rows)
daily |>
  count(date, platform, product_id) |>
  filter(n > 1)

# ---- 2. Benchmarks from the days before Nov 11 ---------------------------

# "30-day" window. Our scraping started Oct 19, so it holds at most 23 days.
before_30d <- daily |>
  filter(date >= event_day - 30, date < event_day) |>
  group_by(platform, product_id) |>
  summarize(
    prev_min = min(lowest_shown_price, na.rm = TRUE),       # EU rule
    prev_median = median(lowest_shown_price, na.rm = TRUE), # typical price
    max_sale = max(sale_price, na.rm = TRUE),               # highest price charged
    days_seen = n(),
    .groups = "drop"
  )

# 7-day window (robustness check only)
before_7d <- daily |>
  filter(date >= event_day - 7, date < event_day) |>
  group_by(platform, product_id) |>
  summarize(
    min_7d = min(lowest_shown_price, na.rm = TRUE),
    avg_7d = mean(lowest_shown_price, na.rm = TRUE),
    days_seen_7d = n(),
    .groups = "drop"
  )

# Verify: the keys are unique before joining (both should print 0 rows)
before_30d |> count(platform, product_id) |> filter(n > 1)
before_7d |> count(platform, product_id) |> filter(n > 1)

# ---- 3. Nov 11 listings ---------------------------------------------------

nov11 <- daily |>
  filter(date == event_day) |>
  inner_join(before_30d, by = c("platform", "product_id")) |>
  left_join(before_7d, by = c("platform", "product_id"))

nrow(nov11)                         # 286 listings with a benchmark
summary(nov11$days_seen)            # 20 to 23 days seen before Nov 11
sum(is.na(nov11$original_price))    # 32 show no crossed-out price

# Advertised discounts: a crossed-out price above the sale price.
# Claimed % off = 1 - sale price / crossed-out price.
advertised <- nov11 |>
  filter(!is.na(original_price), sale_price < original_price) |>
  mutate(claimed_discount = 1 - sale_price / original_price)

nrow(advertised)                    # 207 advertised discounts
advertised |> count(platform)

# ---- 4. Figure 1: what the store claims vs what the price history shows ---

# Real % off = 1 - Nov 11 lowest shown price / benchmark.
# BigGo-style comparisons use lowest_shown_price, never sale_price.
fig1_data <- advertised |>
  select(platform, product_id, claimed_discount, lowest_shown_price,
         prev_min, prev_median) |>
  pivot_longer(
    cols = c(prev_min, prev_median),
    names_to = "benchmark",
    values_to = "benchmark_price"
  ) |>
  mutate(
    real_discount = 1 - lowest_shown_price / benchmark_price,
    status = if_else(lowest_shown_price < benchmark_price,
                     "Lower than before (real discount)",
                     if_else(lowest_shown_price == benchmark_price,
                             "Same as before",
                             "Higher than before")),
    status = factor(status, levels = c("Lower than before (real discount)",
                                       "Same as before",
                                       "Higher than before")),
    benchmark_label = if_else(benchmark == "prev_min",
                              "A. vs lowest earlier price (EU rule)",
                              "B. vs median earlier price")
  )

# Verify: 207 listings x 2 benchmarks = 414 rows, no NA
nrow(fig1_data)
fig1_data |> filter(is.na(real_discount))
fig1_data |> count(benchmark, status)

ggplot(fig1_data, aes(x = claimed_discount, y = real_discount)) +
  geom_hline(yintercept = 0, color = "gray") +
  geom_abline(intercept = 0, slope = 1, linetype = 2) +
  geom_point(mapping = aes(color = status), alpha = 0.6, size = 2) +
  annotate("text", x = 0.22, y = 0.47,
           label = "If the claim were real,\ndots would sit on this line",
           size = 2.8) +
  facet_wrap(~ benchmark_label, nrow = 1) +
  scale_x_continuous(labels = scales::percent) +
  scale_y_continuous(labels = scales::percent) +
  scale_color_manual(values = c("Lower than before (real discount)" = "steelblue",
                                "Same as before" = "gray50",
                                "Higher than before" = "indianred")) +
  labs(x = "Claimed discount (% off the crossed-out price)",
       y = "Real discount (% off the price before Nov 11)",
       color = "Nov 11 price was",
       title = "Store claims vs. real price drops on Double 11",
       subtitle = "207 advertised discounts on momo and PChome, Nov 11, 2026",
       caption = "Source: The Janggals scrapes, 15:07 run, Oct 19 to Nov 11, 2026")

# ---- 5. Figure 2: does the discount count as real under other rules? ------

rule_checks <- advertised |>
  mutate(
    pass_eu_min   = lowest_shown_price < prev_min,
    pass_median   = lowest_shown_price < prev_median,
    pass_charged  = max_sale >= original_price,
    pass_min_7d   = lowest_shown_price < min_7d,
    pass_avg_7d   = lowest_shown_price < avg_7d
  )

rule_labels <- tibble(
  rule = c("eu_min", "median", "charged", "min_7d", "avg_7d"),
  rule_label = c("Below lowest earlier price (EU)",
                 "Below median earlier price",
                 "Crossed-out price charged before (US)",
                 "Below lowest price, last 7 days",
                 "Below average price, last 7 days"),
  rule_type = c("Main benchmark", "Main benchmark", "Other rule",
                "Robustness check", "Robustness check")
)

rule_share <- rule_checks |>
  summarize(across(starts_with("pass_"), ~ mean(.x, na.rm = TRUE))) |>
  pivot_longer(cols = everything(),
               names_to = "rule",
               values_to = "share_real",
               names_prefix = "pass_") |>
  left_join(rule_labels, by = "rule")

# Verify: 5 rules, no NA
rule_share

ggplot(rule_share, aes(x = share_real,
                       y = fct_reorder(rule_label, share_real))) +
  geom_col(mapping = aes(fill = rule_type)) +
  geom_text(aes(label = scales::percent(share_real, accuracy = 1)),
            hjust = -0.2, size = 3.5) +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_fill_manual(values = c("Main benchmark" = "steelblue",
                               "Other rule" = "#5f2167",
                               "Robustness check" = "gray60")) +
  labs(x = "Share of the 207 advertised discounts that count as real",
       y = NULL,
       fill = "Type of rule",
       title = "How many discounts are real? It depends on the rule",
       subtitle = "Every listing here showed a crossed-out price on Nov 11, 2026",
       caption = "Source: The Janggals scrapes, 15:07 run, Oct 19 to Nov 11, 2026")

# ---- 6. Table: the same rules by platform ----------------------------------

rule_by_platform <- rule_checks |>
  group_by(platform) |>
  summarize(
    n = n(),
    claimed = mean(claimed_discount),
    across(starts_with("pass_"), ~ mean(.x, na.rm = TRUE)),
    .groups = "drop"
  )

rule_by_platform
