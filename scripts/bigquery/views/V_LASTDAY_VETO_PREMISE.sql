-- V_LASTDAY_VETO_PREMISE — DOES A POOR FILLING DAY PREDICT A POOR SETTLED DAY?
--
-- THE CLAIM UNDER TEST (Ori 2026-08-17, the last-day veto): the newest ads day may HOLD a move
-- but never drive one. At more than veto_clk1 of its own clicks, a filling day under the raise
-- bar holds a raise; a filling day at or above the cut bar holds a cut. The raise arm rests on
-- one premise and one only: THAT A POOR FILLING READING IS EVIDENCE OF A POOR DAY. If a filling
-- 0.00x usually resolves to a healthy number once attribution accrues, the arm is firing on
-- attribution lag rather than on performance.
--
-- WHY THIS IS A VIEW AND NOT AN EXPERIMENT: a control group for a ONE-DAY DELAY on a few dozen
-- keyword-days is invisible next to the whole-engine holdout's own MDE, and would forgo real
-- value to buy noise. The premise, unlike the effect, is falsifiable on data already held.
--
-- ══ THE OBSTACLE, STATED PLAINLY ═════════════════════════════════════════════════════════════
-- FACT_AMAZON_ADS IS RESTATED IN PLACE. There is no keyword-grain as-of history anywhere in the
-- warehouse: FACT_ADS_RESTATEMENT is (report_date, snapshot_at, channel) — account grain, three
-- samples a day — and FACT_KEYWORD_STATE / FACT_KEYWORD_GUARD snapshot only settled 90-day
-- aggregates. FACT_ENGINE_PROPOSALS quotes the filling reading verbatim inside a vetoed row's
-- reason, but until v27.98 the veto ERASED those rows, so the six snapshots that exist carry
-- essentially none of them. A DIRECT RECONSTRUCTION OF "WHAT KEYWORD K'S DAY D READ AT AGE 1"
-- IS THEREFORE NOT POSSIBLE. This view does not pretend otherwise; it reconstructs the filling
-- reading from the settled row plus the MEASURED account accrual, the same as-seen technique the
-- 3-vs-7 peak-window study used (DE_PEAK_WINDOW_RULE).
--
-- ══ THE INSTRUMENT ═══════════════════════════════════════════════════════════════════════════
-- For a FULLY SETTLED keyword-day we know its final clicks, spend, orders and gross profit. What
-- the engine saw at age 1 is that same day THINNED: V_ADS_SETTLE_CURVE measures, per channel,
-- what share of a day's final spend and final sales are visible one day later. Spend closes
-- early; sales keep accruing across the attribution window. So:
--     spend_1d  ≈ spend_settled × spend_fill        (spend_fill  = age-1 spend share, measured)
--     orders_1d ~ Binomial(orders_settled, sales_fill)   (sales_fill = age-1 sales share, measured)
--     roas_1d   ≈ gp_roas_settled × (orders_1d / orders_settled) / spend_fill
-- Orders are treated as EXCHANGEABLE within the day — each settled order is independently either
-- already attributed at age 1 or not. That is the whole model, and it makes every quantity below
-- a CLOSED FORM rather than a simulation:
--     P(the filling day reads exactly 0.00x)      = (1 − sales_fill) ^ orders_settled
--     P(the filling day reads under the raise bar) = BinomCDF(j* − 1; orders_settled, sales_fill)
--     P(the filling day reads at/above the cut bar) = 1 − BinomCDF(j*cut − 1; …)
-- where j* is the number of orders that must ALREADY be attributed for the filling reading to
-- clear the bar. Both CDFs are computed inline from log-factorials — no UDF, no simulation, and
-- the arithmetic is reproducible by hand on any single row.
--
-- READ THE SIGN OF EVERY APPROXIMATION BEFORE READING THE ANSWER:
--  · sales_fill and spend_fill are ACCOUNT medians applied to every keyword-day. A keyword whose
--    buyers decide faster than the account settles faster than modelled, and vice versa. The
--    model therefore describes the AVERAGE keyword-day and understates the tails in both
--    directions. V_LASTDAY_VETO_LAG_OBSERVED exists to test exactly this assumption against
--    per-keyword attribution lag actually reported by Amazon.
--  · exchangeable orders ignores that a day's LAST click has less time to convert than its first.
--    That makes the model OPTIMISTIC about the filling day (real filling days are worse), which
--    biases every finding below IN THE VETO'S FAVOUR.
--  · gross profit per order is taken as flat within the day, so a day whose late order is its
--    biggest is modelled as milder than it was — again in the veto's favour.
--  · the population is EVERY at-volume SP/SB keyword-day, not the subset on which the engine
--    happened to propose a raise or a cut that morning. The veto only ever fires on a published
--    move, so read every probability here as CONDITIONAL on the engine having proposed one.
--  · settled means the day is older than the SB attribution window plus slack. Fresher days are
--    excluded outright — there is no "nearly settled" row in this view.
--
-- GRAIN: one row per (campaign_id, targeting, date) — the engine's own last-day grain (see the
-- tsig CTE of V_OOB_KEYWORD, which reads clk1/roas1 at exactly this grain, GP-ROAS on the stored
-- FACT_AMAZON_ADS.GROSS_PROFIT column over Ads_cost).
-- Read V_LASTDAY_VETO_PREMISE_READOUT for the answer; read this view to audit a single row.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LASTDAY_VETO_PREMISE` AS
WITH
bars AS (
  SELECT 10  AS veto_clk1,             -- the veto's own real-volume bar (V_OOB_KEYWORD lastday CTE)
         0.5 AS raise_bar,             -- a published RAISE waits a day under this
         1.2 AS cut_bar,               -- a published CUT waits a day at/above this
         3.0 AS min_expected_orders,   -- v27.76 expected-orders gate on the ambiguous 0.00x branch
         30  AS settled_slack_days,    -- a day is judged only once it is older than this
         DATE '2025-09-01' AS from_date
),
-- the MEASURED accrual, read live so no number is pinned here
curve AS (
  SELECT channel,
         MAX(spend_pct_of_final_median) / 100 AS spend_fill,
         MAX(sales_pct_of_final_median) / 100 AS sales_fill,
         MAX(spend_pct_worst)           / 100 AS spend_fill_worst
  FROM `onyga-482313.OI.V_ADS_SETTLE_CURVE`
  WHERE age_days = 1 AND channel IN ('SP', 'SB')
  GROUP BY channel
),
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- settled keyword-days at the engine's last-day grain
kd AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
         a.targeting,
         a.date,
         ANY_VALUE(a.campaign_name) AS campaign_name,
         ANY_VALUE(a.campaign_type) AS channel,
         SUM(a.Ads_clicks)   AS clk,
         SUM(a.Ads_cost)     AS sp,
         SUM(a.Ads_orders)   AS ord,
         SUM(a.Ads_sales)    AS sales,
         SUM(a.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, bars b
  WHERE a.date >= b.from_date
    AND a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 30 DAY)
    AND a.targeting IS NOT NULL
    AND a.campaign_type IN ('SP', 'SB')
  GROUP BY 1, 2, 3
),
-- the keyword's OWN complete-day 90d order rate, as the v27.76 gate uses it (days before this one)
rate AS (
  SELECT kd.*,
         SUM(kd.ord) OVER w AS ord90,
         SUM(kd.clk) OVER w AS clk90
  FROM kd
  WINDOW w AS (PARTITION BY kd.campaign_id, kd.targeting
               ORDER BY UNIX_DATE(kd.date)
               RANGE BETWEEN 90 PRECEDING AND 1 PRECEDING)
),
model AS (
  SELECT
    r.campaign_id, r.campaign_name, r.targeting, r.date, r.channel,
    r.clk AS clicks_settled, ROUND(r.sp, 2) AS spend_settled, r.ord AS orders_settled,
    ROUND(r.sales, 2) AS sales_settled, ROUND(r.gp, 2) AS gp_settled,
    COALESCE(r.clk90, 0) AS clk90, COALESCE(r.ord90, 0) AS ord90,
    c.spend_fill, c.sales_fill, c.spend_fill_worst,
    ROUND(SAFE_DIVIDE(r.gp, NULLIF(r.sp, 0)), 4) AS settled_gp_roas,
    -- the filling day's own clicks, modelled: clicks fill with spend
    r.clk * c.spend_fill AS clicks_1d_model,
    -- how many of the day's settled orders must ALREADY be attributed for the filling reading
    -- to clear each bar.  reading = settled_gp_roas * (j/ord) / spend_fill
    IF(r.ord = 0 OR COALESCE(SAFE_DIVIDE(r.gp, NULLIF(r.sp, 0)), 0) <= 0, r.ord + 1,
       CAST(CEIL(b.raise_bar * c.spend_fill * r.ord / SAFE_DIVIDE(r.gp, NULLIF(r.sp, 0))) AS INT64)
      ) AS jstar_raise,
    IF(r.ord = 0 OR COALESCE(SAFE_DIVIDE(r.gp, NULLIF(r.sp, 0)), 0) <= 0, r.ord + 1,
       CAST(CEIL(b.cut_bar   * c.spend_fill * r.ord / SAFE_DIVIDE(r.gp, NULLIF(r.sp, 0))) AS INT64)
      ) AS jstar_cut,
    b.veto_clk1, b.raise_bar, b.cut_bar, b.min_expected_orders
  FROM rate r
  JOIN curve c ON c.channel = r.channel
  CROSS JOIN bars b
),
prob AS (
  SELECT
    m.*,
    -- P(the filling day reads EXACTLY 0.00x) — no order attributed yet
    POW(1 - m.sales_fill, m.orders_settled) AS p_reads_zero,
    -- BinomCDF(jstar_raise - 1; orders_settled, sales_fill) = P(filling reading under the raise bar)
    (SELECT SUM(EXP(
        (SELECT COALESCE(SUM(LN(x)), 0) FROM UNNEST(GENERATE_ARRAY(1, m.orders_settled)) x)
      - (SELECT COALESCE(SUM(LN(x)), 0) FROM UNNEST(GENERATE_ARRAY(1, i)) x)
      - (SELECT COALESCE(SUM(LN(x)), 0) FROM UNNEST(GENERATE_ARRAY(1, m.orders_settled - i)) x)
      + i * LN(m.sales_fill) + (m.orders_settled - i) * LN(1 - m.sales_fill)))
     FROM UNNEST(GENERATE_ARRAY(0, m.jstar_raise - 1)) i
     WHERE i <= m.orders_settled) AS p_under_raise_bar,
    -- 1 - BinomCDF(jstar_cut - 1; ...) = P(filling reading at/above the cut bar)
    1 - COALESCE((SELECT SUM(EXP(
        (SELECT COALESCE(SUM(LN(x)), 0) FROM UNNEST(GENERATE_ARRAY(1, m.orders_settled)) x)
      - (SELECT COALESCE(SUM(LN(x)), 0) FROM UNNEST(GENERATE_ARRAY(1, i)) x)
      - (SELECT COALESCE(SUM(LN(x)), 0) FROM UNNEST(GENERATE_ARRAY(1, m.orders_settled - i)) x)
      + i * LN(m.sales_fill) + (m.orders_settled - i) * LN(1 - m.sales_fill)))
     FROM UNNEST(GENERATE_ARRAY(0, m.jstar_cut - 1)) i
     WHERE i <= m.orders_settled), 0) AS p_at_or_above_cut_bar
  FROM model m
)
SELECT
  p.campaign_id, p.campaign_name, p.targeting, p.date, p.channel,
  p.clicks_settled, p.spend_settled, p.orders_settled, p.sales_settled, p.gp_settled,
  p.settled_gp_roas,
  ROUND(p.clicks_1d_model, 1) AS clicks_1d_model,
  p.clk90, p.ord90,
  -- the v27.76 gate, computed exactly as V_OOB_KEYWORD computes it
  ROUND(p.clicks_1d_model * COALESCE(SAFE_DIVIDE(p.ord90, NULLIF(p.clk90, 0)), 0), 2) AS expected_orders_1d,
  p.clicks_1d_model > p.veto_clk1 AS at_volume,
  ROUND(p.p_reads_zero, 6)          AS p_reads_zero,
  ROUND(p.p_under_raise_bar, 6)     AS p_under_raise_bar,
  ROUND(p.p_at_or_above_cut_bar, 6) AS p_at_or_above_cut_bar,
  -- the RAISE arm as v27.75 shipped it: any reading under the bar holds the raise
  ROUND(p.p_under_raise_bar, 6) AS p_veto_raise_v75,
  -- the RAISE arm as v27.76 gates it: a 0.00x reading only vetoes when the zero is SURPRISING
  ROUND(GREATEST(p.p_under_raise_bar - IF(
      p.clicks_1d_model * COALESCE(SAFE_DIVIDE(p.ord90, NULLIF(p.clk90, 0)), 0) >= p.min_expected_orders,
      0, p.p_reads_zero), 0), 6) AS p_veto_raise_v76,
  ROUND(p.p_at_or_above_cut_bar, 6) AS p_veto_cut,
  -- did the day actually turn out fine, judged at the veto's OWN bars once settled?
  p.settled_gp_roas >= p.raise_bar AS settled_clears_raise_bar,
  p.settled_gp_roas >= 1.0         AS settled_clears_breakeven,
  p.settled_gp_roas <  p.cut_bar   AS settled_under_cut_bar,
  -- the arithmetic floor the CUT arm buys: a filling day reading at/above the cut bar cannot
  -- settle below cut_bar x spend_fill, because the only way the reading can OVERSTATE the day
  -- is the spend that has not landed yet.
  ROUND(p.cut_bar * p.spend_fill, 4)       AS cut_arm_settled_floor,
  ROUND(p.cut_bar * p.spend_fill_worst, 4) AS cut_arm_settled_floor_worst_fill,
  p.spend_fill, p.sales_fill, p.spend_fill_worst,
  p.veto_clk1, p.raise_bar, p.cut_bar, p.min_expected_orders
FROM prob p;
