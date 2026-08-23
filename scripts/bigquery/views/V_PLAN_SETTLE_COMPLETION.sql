-- =============================================================================================
-- V_PLAN_SETTLE_COMPLETION — v27.133 (2026-08-23): "how much of this day's ads sales had arrived
-- when we read it?", per channel and per age in days. ONE ROW PER (channel, age_days).
--
-- WHY IT EXISTS (spec P-14a). A window read the day after it closes has not seen its own orders:
-- ads sales accrue across the attribution window (SP ~7 days, SB ~14). A plan that judges such a
-- window as it reads calls a keyword not-good for the crime of being recent, and parks it. So the
-- plan divides each window day's gross profit by the completion factor for that day's age.
--
-- THE FACTOR IS READ, NEVER DECLARED. It comes from V_ADS_SETTLE_CURVE, the house's published
-- measurement of restatement (first sample at each age vs the latest sample held), through three
-- treatments that make a measured curve safe to divide by:
--   FORWARD FILL   ages the curve has not measured take the last age it did measure.
--   MONOTONE       the published medians wobble by a point either way (a later age can read
--                  lower than an earlier one, which is noise, not evidence that sales vanished).
--                  A running MAX makes the factor non-decreasing in age, so an older day is never
--                  corrected harder than a younger one.
--   CAP AND FLOOR  capped at 1.0 (a day is never more than complete). Floored at the declared
--                  FACTOR_FLOOR below so no rebuilt curve can ever inflate a window more than
--                  twofold. The floor is not expected to bind: by P-10 and the P-14a fence no
--                  window day is younger than age 2, and the curve's age-2 medians sit far above
--                  it — read them, do not take a number from this header (Standing Rule 0):
--                    SELECT channel, age_days, sales_pct_of_final_median, spend_pct_of_final_median
--                    FROM `onyga-482313.OI.V_ADS_SETTLE_CURVE` WHERE age_days <= 3 ORDER BY 1, 2;
-- Beyond the curve's last measured age the factor is 1.0 by construction (the curve covers the
-- whole attribution window; anything older is settled).
--
-- HONESTY COLUMN. curve_available is FALSE when the curve cannot answer for this channel and age
-- — too few report dates behind the median, or no curve at all (V_ADS_SETTLE_CURVE needs several
-- days of SP_SNAPSHOT_ADS_RESTATEMENT samples before it says anything). The factor is then 1.0
-- and the consumer says so on the row: the plan falls back to the asymmetric guard (P-14b) alone.
--
-- SPEND IS PUBLISHED TOO, and is NOT used to correct anything: the same curve shows spend at
-- essentially its final value by age 2, which is why the plan corrects gross profit only. It is
-- carried here so a reader (and the acceptance) can check that claim against the curve itself
-- rather than against a sentence in a header.
--
-- Declared constants (Standing Rule 0 exempt):
--   MIN_REPORT_DATES 8  — the median needs a week-plus of report dates behind it to be read as a
--                         factor rather than as a rumour.
--   FACTOR_FLOOR   0.50 — the twofold inflation cap described above.
--   MAX_AGE         120 — the grid this view publishes; older days are settled by any measure.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-14a, §3a.
-- SOP: architecture/NEXT_WEEK_MONEY.md §2.
-- Acceptance: scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql (C09, C10).
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION`
OPTIONS (description = "v27.133 (2026-08-23): the settle-completion factor the next-week money plan divides a window day's gross profit by, one row per (channel SP|SB, age_days 0..120). Read from V_ADS_SETTLE_CURVE (sales_pct_of_final_median), forward-filled over unmeasured ages, made monotone in age by a running MAX, capped at 1.0 and floored at a declared 0.50 so no rebuilt curve can inflate a window more than twofold; 1.0 beyond the curve's last measured age. curve_available says whether the curve could actually answer (enough report dates behind the median) — FALSE means the factor is 1.0 and the plan rests on the asymmetric guard alone (spec P-14a). spend_completion is published for reading and for the acceptance only: spend is at its final value by age 2, which is why only gross profit is corrected. Read by V_PLAN_WINDOW_JUDGMENT. Spec P-14a, §3a. SOP: architecture/NEXT_WEEK_MONEY.md")
AS
WITH k AS (
  SELECT 8 AS min_report_dates, 0.50 AS factor_floor, 120 AS max_age
),
raw AS (
  SELECT channel,
         age_days,
         SAFE_DIVIDE(sales_pct_of_final_median, 100) AS f_sales,
         SAFE_DIVIDE(spend_pct_of_final_median, 100) AS f_spend,
         report_dates
  FROM `onyga-482313.OI.V_ADS_SETTLE_CURVE`
  WHERE channel IN ('SP', 'SB')
),
bounds AS (
  SELECT channel, MAX(age_days) AS curve_max_age
  FROM raw
  GROUP BY 1
),
grid AS (
  SELECT ch AS channel, age AS age_days
  FROM k, UNNEST(['SP', 'SB']) AS ch, UNNEST(GENERATE_ARRAY(0, k.max_age)) AS age
),
joined AS (
  SELECT g.channel, g.age_days, r.f_sales, r.f_spend, r.report_dates, b.curve_max_age
  FROM grid g
  LEFT JOIN raw r ON r.channel = g.channel AND r.age_days = g.age_days
  LEFT JOIN bounds b ON b.channel = g.channel
),
filled AS (
  SELECT j.*,
         LAST_VALUE(f_sales IGNORE NULLS) OVER w AS f_sales_ff,
         LAST_VALUE(f_spend IGNORE NULLS) OVER w AS f_spend_ff,
         LAST_VALUE(report_dates IGNORE NULLS) OVER w AS report_dates_ff
  FROM joined j
  WINDOW w AS (PARTITION BY channel ORDER BY age_days ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),
mono AS (
  SELECT f.*,
         MAX(f_sales_ff) OVER w AS f_sales_mono,
         MAX(f_spend_ff) OVER w AS f_spend_mono
  FROM filled f
  WINDOW w AS (PARTITION BY channel ORDER BY age_days ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  m.channel,
  m.age_days,
  CASE
    WHEN m.curve_max_age IS NULL THEN 1.0
    WHEN m.age_days > m.curve_max_age THEN 1.0
    WHEN m.f_sales_mono IS NULL THEN 1.0
    ELSE LEAST(1.0, GREATEST((SELECT factor_floor FROM k), m.f_sales_mono))
  END AS sales_completion,
  CASE
    WHEN m.curve_max_age IS NULL THEN 1.0
    WHEN m.age_days > m.curve_max_age THEN 1.0
    WHEN m.f_spend_mono IS NULL THEN 1.0
    ELSE LEAST(1.0, GREATEST((SELECT factor_floor FROM k), m.f_spend_mono))
  END AS spend_completion,
  CASE
    WHEN m.curve_max_age IS NOT NULL AND m.age_days > m.curve_max_age THEN TRUE
    WHEN m.f_sales_mono IS NULL THEN FALSE
    WHEN COALESCE(m.report_dates_ff, 0) < (SELECT min_report_dates FROM k) THEN FALSE
    ELSE TRUE
  END AS curve_available,
  CASE
    WHEN m.curve_max_age IS NULL THEN 'NO_CURVE'
    WHEN m.age_days > m.curve_max_age THEN 'BEYOND_CURVE'
    WHEN m.f_sales_mono IS NULL THEN 'NO_CURVE'
    WHEN COALESCE(m.report_dates_ff, 0) < (SELECT min_report_dates FROM k) THEN 'THIN_CURVE'
    ELSE 'CURVE'
  END AS factor_source,
  COALESCE(m.report_dates_ff, 0) AS report_dates
FROM mono m
ORDER BY channel, age_days;
