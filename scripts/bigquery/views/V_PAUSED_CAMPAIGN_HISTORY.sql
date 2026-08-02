-- V_PAUSED_CAMPAIGN_HISTORY — historic performance of PAUSED campaigns for the Weekly Run
-- "Seasonal Paused" + "Other" sections (Ori 2026-08-02, SOP OOB_BUDGET_PHASE.md §v12).
-- One row per (paused campaign, target text) from FACT history (what actually ran), plus a
-- campaign rollup row (target_text IS NULL). Display-only — nothing spends while paused, so
-- there are no actions here; the windows are HISTORIC:
--   m1 = last 28 days · m3 = last 91 days · y1 = last 365 days
--   season_* = the campaign's RELEVANT SEASON, most recent completed occurrence (Seasonal
--   Paused shows ONLY this window): campaign name token -> DIM_US_HOLIDAYS holiday, window
--   [pre_season_start, COALESCE(cooldown_end, holiday_date)] of the latest occurrence that
--   already started. Net ROAS estimated via the mapped-ASIN cost ratio (same method as the
--   SB launch views / V_OOB_KEYWORD prod CTE).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PAUSED_CAMPAIGN_HISTORY` AS
WITH camps AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_name,
         campaign_type AS channel, daily_budget AS budget,
         LOWER(campaign_name) LIKE '%brand defense%' AS is_defense,
         REGEXP_CONTAINS(LOWER(campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal,
         -- campaign name token -> holiday_name in DIM_US_HOLIDAYS
         CASE
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'christmas|xmas|santa|advent') THEN 'Christmas'
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'valentine') THEN "Valentine's Day"
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'easter') THEN 'Easter'
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'halloween') THEN 'Halloween'
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'thanksgiving') THEN 'Thanksgiving'
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'black friday|bfcm') THEN 'Black Friday'
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'cyber monday') THEN 'Cyber Monday'
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'back to school') THEN 'Back to School'
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'mother.?s day') THEN "Mother's Day"
           WHEN REGEXP_CONTAINS(LOWER(campaign_name), r'father.?s day') THEN "Father's Day"
         END AS season_holiday
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE campaign_state = 'PAUSED'
),
-- the most recent occurrence of each holiday whose season has already STARTED (its window may
-- still be running — e.g. Back to School in August shows the in-flight season so far)
season AS (
  SELECT holiday_name,
         ARRAY_AGG(STRUCT(pre_season_start AS s, COALESCE(cooldown_end, holiday_date) AS e)
                   ORDER BY holiday_date DESC LIMIT 1)[OFFSET(0)] AS w
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE pre_season_start <= CURRENT_DATE('America/Los_Angeles')
  GROUP BY holiday_name
),
prod AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid,
    SAFE_DIVIDE(ANY_VALUE(c.cost), NULLIF(ANY_VALUE(p.listing_price_amount), 0)) AS cost_ratio
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN (SELECT asin, TOTAL_COST_PER_UNIT cost FROM (
      SELECT asin, TOTAL_COST_PER_UNIT, ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY` WHERE marketplace_id='ATVPDKIKX0DER' AND end_date IS NULL) WHERE rn=1) c
    ON c.asin = f.ASIN_BY_CAMPAIGN_NAME
  GROUP BY 1
),
today AS (SELECT CURRENT_DATE('America/Los_Angeles') AS d),
hist AS (
  SELECT CAST(f.campaign_id AS STRING) AS campaign_id,
         LOWER(TRIM(f.targeting)) AS target_text,
         f.date, SUM(f.Ads_clicks) clk, SUM(f.Ads_cost) sp, SUM(f.Ads_sales) sales, SUM(f.Ads_orders) ord
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN camps c ON CAST(f.campaign_id AS STRING) = c.campaign_id
  WHERE f.date >= DATE_SUB((SELECT d FROM today), INTERVAL 365 DAY)
  GROUP BY 1, 2, 3
),
-- keyword grain + campaign rollup (target_text NULL) in one pass
agg AS (
  SELECT h.campaign_id, tt AS target_text,
    SUM(IF(h.date >= DATE_SUB((SELECT d FROM today), INTERVAL 28 DAY), h.clk, 0)) clk_m1,
    ROUND(SUM(IF(h.date >= DATE_SUB((SELECT d FROM today), INTERVAL 28 DAY), h.sp, 0)), 2) sp_m1,
    SUM(IF(h.date >= DATE_SUB((SELECT d FROM today), INTERVAL 28 DAY), h.sales, 0)) sales_m1,
    SUM(IF(h.date >= DATE_SUB((SELECT d FROM today), INTERVAL 91 DAY), h.clk, 0)) clk_m3,
    ROUND(SUM(IF(h.date >= DATE_SUB((SELECT d FROM today), INTERVAL 91 DAY), h.sp, 0)), 2) sp_m3,
    SUM(IF(h.date >= DATE_SUB((SELECT d FROM today), INTERVAL 91 DAY), h.sales, 0)) sales_m3,
    SUM(h.clk) clk_y1, ROUND(SUM(h.sp), 2) sp_y1, SUM(h.sales) sales_y1, SUM(h.ord) ord_y1,
    SUM(IF(s.w.s IS NOT NULL AND h.date BETWEEN s.w.s AND s.w.e, h.clk, 0)) clk_season,
    ROUND(SUM(IF(s.w.s IS NOT NULL AND h.date BETWEEN s.w.s AND s.w.e, h.sp, 0)), 2) sp_season,
    SUM(IF(s.w.s IS NOT NULL AND h.date BETWEEN s.w.s AND s.w.e, h.sales, 0)) sales_season,
    SUM(IF(s.w.s IS NOT NULL AND h.date BETWEEN s.w.s AND s.w.e, h.ord, 0)) ord_season
  FROM hist h
  JOIN camps c ON c.campaign_id = h.campaign_id
  LEFT JOIN season s ON s.holiday_name = c.season_holiday
  CROSS JOIN UNNEST([h.target_text, CAST(NULL AS STRING)]) AS tt
  GROUP BY 1, 2
)
SELECT
  c.campaign_id, c.campaign_name, c.channel, ROUND(c.budget, 2) AS budget,
  c.is_defense, c.is_seasonal, c.season_holiday,
  s.w.s AS season_start, s.w.e AS season_end,
  a.target_text,
  a.clk_m1 AS clicks_m1, a.sp_m1 AS spend_m1,
  ROUND(SAFE_DIVIDE(a.sales_m1 * (1 - COALESCE(pr.cost_ratio, 0)), NULLIF(a.sp_m1, 0)), 2) AS roas_m1,
  a.clk_m3 AS clicks_m3, a.sp_m3 AS spend_m3,
  ROUND(SAFE_DIVIDE(a.sales_m3 * (1 - COALESCE(pr.cost_ratio, 0)), NULLIF(a.sp_m3, 0)), 2) AS roas_m3,
  a.clk_y1 AS clicks_y1, a.sp_y1 AS spend_y1, a.ord_y1 AS orders_y1,
  ROUND(SAFE_DIVIDE(a.sales_y1 * (1 - COALESCE(pr.cost_ratio, 0)), NULLIF(a.sp_y1, 0)), 2) AS roas_y1,
  a.clk_season AS clicks_season, a.sp_season AS spend_season, a.ord_season AS orders_season,
  ROUND(SAFE_DIVIDE(a.sales_season * (1 - COALESCE(pr.cost_ratio, 0)), NULLIF(a.sp_season, 0)), 2) AS roas_season
FROM camps c
LEFT JOIN agg a ON a.campaign_id = c.campaign_id
LEFT JOIN season s ON s.holiday_name = c.season_holiday
LEFT JOIN prod pr ON pr.cid = c.campaign_id;
