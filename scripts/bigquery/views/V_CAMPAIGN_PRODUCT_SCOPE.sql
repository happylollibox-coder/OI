-- =============================================
-- V_CAMPAIGN_PRODUCT_SCOPE — HOW MANY OF OUR OWN PRODUCTS DOES THIS CAMPAIGN SELL? (v27.80,
-- 2026-08-17, engine-finalization Task 4.10).
--
-- Ori 2026-08-17: "BALL-SP/AUTO (Mint) is auto per product. auto we have for each product - so no
-- need to change / only reduce ads by reducing the bid."
--
-- THE DISTINCTION THIS OBJECT EXISTS TO MAKE. This account runs ONE AUTO CAMPAIGN PER VARIATION
-- alongside a handful of shared broad/competitor doorways. Those two shapes need OPPOSITE stock
-- treatment and nothing in the warehouse could tell them apart:
--   SHARED DOORWAY (n_own_asins > 1)  — BALLS- BROAD (5 own ASINs), BUNNY - COMPETITORS (11).
--       A dry variation inside it can be swapped for an in-stock sibling: the traffic keeps
--       arriving, it just lands on a product we can ship. RE-AIM (V_LOW_STOCK_REDIRECT).
--   DEDICATED CAMPAIGN (n_own_asins = 1) — BALL-SP/AUTO (Mint), one ASIN and nothing else.
--       There is nowhere to re-aim: BALL-SP/AUTO (Pink) already exists and already does exactly
--       the job a swap would do, so the "swap" would be a duplicate of a live campaign. The only
--       honest lever left is the ORDINARY BRAKE — reduce the bid.
--
-- GRAIN: one row per campaign that served an impression in the window (~120 rows). campaign_id is
-- STRING throughout (fact_oi_product_id_js_precision — ids are 15-digit today but the house rule
-- is CAST AS STRING end-to-end and this object is read by the dashboard).
--
-- OWN vs COMPETITOR: "own" = DIM_PRODUCT.parent_name IS NOT NULL
-- (fact_oi_dim_product_holds_competitor_asins — DIM_PRODUCT also holds tracked competitor ASINs,
-- and a PT/ASIN-targeting campaign legitimately advertises against them). n_own_asins counts ONLY
-- our own products, which is the count the re-aim question turns on: a campaign that advertises
-- one of ours against forty competitor ASINs is still DEDICATED.
--
-- WINDOW: the last 30 COMPLETE days of the advertised-product report, ending adv_watermark − 1
-- (Task 4.7 / feedback_window_convention_complete_days — the last day stands alone because it is
-- still filling). The watermark is the report's OWN MAX(date), not FACT_AMAZON_ADS's: this view
-- reads only the advertised-product report and must not inherit another source's lag. 30 days is
-- long enough that a variation paused for a week still counts as in-scope — the question is "what
-- is this campaign FOR", not "what did it serve yesterday".
--
-- SP ONLY, AND THAT IS A REAL LIMIT, NOT AN OVERSIGHT: Amazon publishes no advertised-product
-- report for Sponsored Brands, so SB/video campaigns (VIDEO- BALL, VIDEO- COMP/BALL,
-- BUNNY-VIDEO/BROAD) get NO ROW here. Consumers must treat a missing row as UNKNOWN and fall back
-- to their existing behaviour — never as n_own_asins = 0, and never as "dedicated". SB creatives
-- carry fixed ASINs and cannot be re-aimed anyway, so the SB gap costs the redirect view nothing;
-- what it does cost is the brake restoration in V_LOW_STOCK_ADS, which stays conservative (still
-- suppressed) on a dedicated SB campaign. Recorded as the known follow-up.
--
-- READ THE TABLE, NOT THE VIEW, FROM ANY HOT PATH: V_LOW_STOCK_ADS sits AT BigQuery's
-- query-planning ceiling (it stopped planning outright on 2026-08-17 and cost a whole repair), so
-- it joins T_CAMPAIGN_PRODUCT_SCOPE — the materialization of this view, rebuilt as orchestrator
-- Task 20.5d3, before anything reads the low-stock engine. House pattern for planner blowups:
-- never inline another view into a ceiling view (fact_oi_cube_table_planner_blowup).
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_PRODUCT_SCOPE` AS
WITH wm AS (
  -- the report's own watermark; the window is the 30 COMPLETE days ending the day before it
  SELECT MAX(date) AS adv_wm
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
),
own AS (
  -- our products only; DIM_PRODUCT also carries tracked competitor ASINs (parent_name IS NULL)
  SELECT DISTINCT asin
  FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE parent_name IS NOT NULL AND asin IS NOT NULL
),
adv AS (
  SELECT
    CAST(a.campaign_id AS STRING) AS campaign_id,
    a.advertised_asin             AS asin,
    SUM(a.impressions)            AS impressions_30d,
    ROUND(SUM(a.spend), 2)        AS spend_30d
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` a
  CROSS JOIN wm
  WHERE a.date BETWEEN DATE_SUB(wm.adv_wm, INTERVAL 30 DAY)
                   AND DATE_SUB(wm.adv_wm, INTERVAL 1 DAY)
    AND a.campaign_id IS NOT NULL
    AND a.advertised_asin IS NOT NULL
  GROUP BY 1, 2
  -- served, not merely enabled: an ad that never showed is not a doorway
  HAVING impressions_30d > 0
)
SELECT
  v.campaign_id,
  (SELECT adv_wm FROM wm)                                    AS adv_watermark,
  DATE_SUB((SELECT adv_wm FROM wm), INTERVAL 30 DAY)         AS window_start,
  DATE_SUB((SELECT adv_wm FROM wm), INTERVAL 1 DAY)          AS window_end,
  CAST(COUNTIF(o.asin IS NOT NULL) AS INT64)                 AS n_own_asins,
  CAST(COUNT(*) AS INT64)                                    AS n_advertised_asins,
  -- THE POINT OF THE VIEW: the single own ASIN of a dedicated campaign, NULL the moment there are
  -- two (a two-product campaign has somewhere to re-aim, so it is not dedicated). MAX() over the
  -- one surviving value is exact, not a pairing — there is exactly one row when the IF fires, so
  -- this is never two ANY_VALUE()s out of one GROUP BY (fact_oi_any_value_pairing_nondeterminism).
  IF(COUNTIF(o.asin IS NOT NULL) = 1,
     MAX(IF(o.asin IS NOT NULL, v.asin, NULL)),
     NULL)                                                   AS sole_asin,
  ARRAY_AGG(IF(o.asin IS NOT NULL, v.asin, NULL)
            IGNORE NULLS ORDER BY v.asin)                    AS own_asins,
  CAST(SUM(IF(o.asin IS NOT NULL, v.impressions_30d, 0)) AS INT64) AS own_impressions_30d,
  ROUND(SUM(IF(o.asin IS NOT NULL, v.spend_30d, 0)), 2)      AS own_spend_30d
FROM adv v
LEFT JOIN own o ON o.asin = v.asin
GROUP BY 1;
