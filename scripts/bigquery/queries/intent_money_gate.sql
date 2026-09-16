-- =============================================================================================
-- INTENT MONEY GATE (plan Task 8). The scorecard measures CVR prediction; this measures money,
-- and it is the one that decides promotion (spec section 6 step 5).
--
-- Week W supplies each keyword's clicks-weighted intent mix; the curve supplies cvr_hat; the
-- margin supplies gp_per_order; week W+1 supplies what actually happened. A keyword-week is
-- judged only when both weeks carry >= 15 clicks, and the CUT rule is judged only on >= 80
-- clicks and >= $60 spend, as in spec section 1.
--
-- TWO MARGINS, REPORTED SIDE BY SIDE, because they answer different questions:
--   *_cat  uses the CATALOG's gp_per_order (T_INTENT_BID_BASE, today's house margin). This is the
--          literal gate the plan wrote: "what would a bid built from today's catalog have said".
--          It conflates the curve with margin drift: the 2026 AOV collapse moved GP-per-order
--          from ~$16.60 (window average) to $13.69 (today), so today's catalog under-prices a
--          spring week by ~1.2x on margin ALONE, whatever the curve says.
--   *_win  uses each product's realised GP-per-order INSIDE the gate window. Same for every
--          curve, so the comparison isolates the CURVE, which is the thing Task 9 promotes.
--          This is the reading recorded 2026-09-01 (1.693 live -> 1.206 shadow at $16.60).
-- PASS BAR (plan Task 8): under_pricing <= 1.15 AND false_cut_rate below the live baseline (54%).
--
-- CPU: NEVER point `curve` at a VIEW. V_INTENT_CVR_CURVE and _SHADOW cost ~27k CPU-seconds per
-- scan and this query inlining one was REJECTED on 2026-09-01 (50,413 CPU-s against the on-demand
-- ceiling). Materialise the curve first (T_INTENT_CVR_CURVE is already a table; a shadow variant
-- is a CREATE OR REPLACE TABLE ... AS <shadow body> into a T_TMP_GATE_* scratch table) and point
-- `curve` at the table. The runner does that; see the 2026-09-12 record in spec section 10.
--
-- Window: 2026-01-05 .. 2026-08-23 (Mondays), the plan's window, kept for comparability with the
-- recorded baseline. The curve is fitted on all history including these weeks -- this gate is
-- in-sample for the base by design; the walk-forward instrument is V_INTENT_INDEX_SCORECARD.
-- =============================================================================================
WITH curve AS (
  SELECT product_short_name, intent_key, month_of_year, cvr_hat
  FROM `onyga-482313.OI.T_INTENT_CVR_CURVE`          -- <== CURVE TABLE (swap to a T_TMP_GATE_* table)
),
gpo_cat AS (
  SELECT product_short_name, intent_key, month_of_year, MAX(gp_per_order) AS gp_per_order
  FROM `onyga-482313.OI.T_INTENT_BID_BASE`
  GROUP BY 1, 2, 3
),
base AS (
  SELECT f.campaign_id, f.targeting,
    DATE_TRUNC(f.date, WEEK(MONDAY)) AS wk, EXTRACT(MONTH FROM f.date) AS mo,
    d.product_short_name, i.intent_key,
    f.Ads_clicks AS clk, f.Ads_cost AS cost, f.Ads_orders AS ord, IFNULL(f.GROSS_PROFIT, 0) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i USING (search_term)
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
    AND f.date BETWEEN DATE '2026-01-05' AND DATE '2026-08-30'   -- W+1 of the last W
),
-- window-correct margin: what an order actually earned, per product, inside the gate window
gpo_win AS (
  SELECT product_short_name, SAFE_DIVIDE(SUM(gp), NULLIF(SUM(ord), 0)) AS gp_per_order
  FROM base GROUP BY 1
),
priced AS (
  SELECT b.*,
    c.cvr_hat * gc.gp_per_order AS vpc_cat,
    c.cvr_hat * gw.gp_per_order AS vpc_win
  FROM base b
  LEFT JOIN curve   c  ON c.product_short_name = b.product_short_name AND c.intent_key = b.intent_key AND c.month_of_year = b.mo
  LEFT JOIN gpo_cat gc ON gc.product_short_name = b.product_short_name AND gc.intent_key = b.intent_key AND gc.month_of_year = b.mo
  LEFT JOIN gpo_win gw ON gw.product_short_name = b.product_short_name
),
kw AS (
  SELECT campaign_id, targeting, wk,
    SUM(clk) AS clk, SUM(cost) AS cost, SUM(gp) AS gp,
    SAFE_DIVIDE(SUM(IF(vpc_cat IS NOT NULL, clk * vpc_cat, 0)), SUM(IF(vpc_cat IS NOT NULL, clk, 0))) AS w_vpc_cat,
    SAFE_DIVIDE(SUM(IF(vpc_win IS NOT NULL, clk * vpc_win, 0)), SUM(IF(vpc_win IS NOT NULL, clk, 0))) AS w_vpc_win,
    SUM(IF(vpc_cat IS NOT NULL, clk, 0)) AS priced_clk
  FROM priced GROUP BY 1, 2, 3
),
pairs AS (
  SELECT a.w_vpc_cat, a.w_vpc_win, b.clk AS n_clk, b.cost AS n_cost, b.gp AS n_gp,
    SAFE_DIVIDE(b.cost, b.clk) AS n_cpc, SAFE_DIVIDE(b.gp, b.cost) AS n_net_roas
  FROM kw a JOIN kw b
    ON b.campaign_id = a.campaign_id AND b.targeting = a.targeting AND b.wk = DATE_ADD(a.wk, INTERVAL 7 DAY)
  WHERE a.w_vpc_cat > 0 AND a.priced_clk >= 15 AND b.clk >= 15
    AND a.wk <= DATE '2026-08-23'
)
SELECT
  COUNT(*)                                                            AS keyword_weeks,
  ROUND(SAFE_DIVIDE(SUM(n_gp), SUM(n_clk)), 4)                       AS actual_vpc,
  ROUND(SAFE_DIVIDE(SUM(n_clk * w_vpc_cat), SUM(n_clk)), 4)          AS predicted_vpc_cat,
  ROUND(SAFE_DIVIDE(SUM(n_gp), SUM(n_clk)) / NULLIF(SAFE_DIVIDE(SUM(n_clk * w_vpc_cat), SUM(n_clk)), 0), 3) AS under_pricing_cat,
  ROUND(SAFE_DIVIDE(SUM(n_clk * w_vpc_win), SUM(n_clk)), 4)          AS predicted_vpc_win,
  ROUND(SAFE_DIVIDE(SUM(n_gp), SUM(n_clk)) / NULLIF(SAFE_DIVIDE(SUM(n_clk * w_vpc_win), SUM(n_clk)), 0), 3) AS under_pricing_win,
  COUNTIF(n_clk >= 80 AND n_cost >= 60)                              AS judgeable,
  ROUND(SAFE_DIVIDE(COUNTIF(n_clk >= 80 AND n_cost >= 60 AND n_cpc > w_vpc_cat * 0.70 AND n_net_roas >= 1),
                    NULLIF(COUNTIF(n_clk >= 80 AND n_cost >= 60), 0)) * 100, 1) AS false_cut_rate_cat,
  ROUND(SAFE_DIVIDE(COUNTIF(n_clk >= 80 AND n_cost >= 60 AND n_cpc > w_vpc_win * 0.70 AND n_net_roas >= 1),
                    NULLIF(COUNTIF(n_clk >= 80 AND n_cost >= 60), 0)) * 100, 1) AS false_cut_rate_win
FROM pairs;
