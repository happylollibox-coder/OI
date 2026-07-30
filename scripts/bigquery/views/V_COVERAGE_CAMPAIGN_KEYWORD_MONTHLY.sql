-- V_COVERAGE_CAMPAIGN_KEYWORD_MONTHLY — per (campaign_id × month × keyword) 12-month P&L.
--
-- Third drill level of the cockpit campaign evidence: cell → campaign → MONTH → KEYWORD.
-- One row per (campaign_id, month, keyword_id) over the LAST 12 MONTHS, so a MonthRow can
-- expand to show WHICH keywords drove that month's spend/performance.
--
-- Grain source is the keyword/targeting feed (targeting_keyword_report — same feed behind
-- V_KEYWORD_DAILY), NOT advertised_product (which has no keyword). Metrics kept consistent
-- with V_COVERAGE_CAMPAIGN_MONTHLY:
--   • spend / clicks / impressions / cpc  → additive raw columns, summed per month.
--   • units = units_sold_clicks_7_d        → the SAME 7-day click-attributed window the
--     campaign month drill uses (units_7d), so keyword units are comparable to the month row.
--   • net_profit / net_roas need a gross-profit-per-unit, but the keyword feed has no ASIN.
--     gp_per_unit is taken at CAMPAIGN grain: a units-weighted blend of the campaign's own
--     advertised ASINs (authoritative asin<->campaign link in advertised_product), falling
--     back to the family-average gp when the campaign sold nothing. Families are gp-tight
--     (e.g. LolliME 12.06–12.11) so the blend is a close approximation, not an exact split.
--
-- NOTE: keyword units are a SUBSET of the campaign's total (auto / product targeting isn't
-- keyword-attributed), so they do NOT reconcile to the month row's units — this is the
-- keyword breakdown, not a decomposition of the month total.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_CAMPAIGN_KEYWORD_MONTHLY` AS
WITH
-- ── Own sellable products + per-ASIN gross profit per unit ──
prod AS (
  SELECT dp.asin, dp.parent_name,
    ROUND(lc.price - COALESCE(ch.TOTAL_COST_PER_UNIT, 0), 2) AS gp_per_unit
  FROM `onyga-482313`.OI.DIM_PRODUCT dp
  LEFT JOIN (
    SELECT asin1, price FROM `onyga-482313`.OI.V_DIM_LISTING_CURRENT
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin1 ORDER BY price DESC) = 1
  ) lc ON lc.asin1 = dp.asin
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT FROM `onyga-482313`.OI.DIM_COSTS_HISTORY
    WHERE end_date IS NULL OR end_date >= CURRENT_DATE()
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
  ) ch ON ch.asin = dp.asin
  WHERE dp.parent_name IS NOT NULL AND dp.parent_name != 'UNKNOWN' AND dp.is_active = true
),
-- ── Family-average gp (fallback when a campaign has no attributed units) ──
fam_gp AS (
  SELECT parent_name, AVG(gp_per_unit) AS gp FROM prod GROUP BY parent_name
),
-- ── Per-campaign advertised context (authoritative asin<->campaign, last 12 months) ──
adv AS (
  SELECT CAST(ap.campaign_id AS STRING) AS campaign_id,
    ap.advertised_asin AS asin, ap.units_7d, ap.cost, p.parent_name, p.gp_per_unit
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product ap
  JOIN prod p ON p.asin = ap.advertised_asin
  WHERE ap.date >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 11 MONTH), MONTH)
),
-- units-weighted blended gp per campaign
camp_gp AS (
  SELECT campaign_id,
    SAFE_DIVIDE(SUM(units_7d * gp_per_unit), NULLIF(SUM(units_7d), 0)) AS gp_weighted
  FROM adv GROUP BY campaign_id
),
-- dominant family per campaign (by ad spend) → family-avg gp fallback
camp_fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT campaign_id, parent_name,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY SUM(cost) DESC) AS rn
    FROM adv GROUP BY campaign_id, parent_name
  ) WHERE rn = 1
),
-- resolved gp_per_unit per campaign: units-weighted blend, else family average
camp_gp_final AS (
  SELECT cf.campaign_id,
    COALESCE(cg.gp_weighted, fg.gp) AS gp_unit
  FROM camp_fam cf
  LEFT JOIN camp_gp cg ON cg.campaign_id = cf.campaign_id
  LEFT JOIN fam_gp fg ON fg.parent_name = cf.parent_name
),
-- ── INTENT PROFITABLE_ROAS floor (target-CPC denominator) ──
floor AS (
  SELECT MAX(CAST(threshold_value AS FLOAT64)) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id IN ('BROAD_SP','BROAD_VIDEO','BROAD_SPOTLIGHT')
),
-- ── Keyword display text + match type ──
kh AS (
  -- 2026-07-30: consolidated source (V_DIM_CAMPAIGN_CURRENT / DIM_*) per prefer-DIM/FACT rule; was fivetran-hl.amazon_ads.keyword_history
  SELECT keyword_id,
    ANY_VALUE(keyword_text) AS keyword_text, ANY_VALUE(match_type) AS match_type
  FROM `onyga-482313`.OI.DIM_KEYWORD WHERE is_current GROUP BY 1
),
-- ── Keyword metrics per (campaign, month, keyword), last 12 months ──
kwm AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
    DATE_TRUNC(date, MONTH) AS month,
    CAST(keyword_id AS STRING) AS keyword_id,
    SUM(impressions) AS impressions, SUM(clicks) AS clicks,
    SUM(cost) AS cost, SUM(units_sold_clicks_7_d) AS units
  FROM `fivetran-hl.amazon_ads.targeting_keyword_report`
  WHERE date >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 11 MONTH), MONTH)
    AND keyword_id IS NOT NULL
  GROUP BY 1, 2, 3
)
SELECT
  kwm.campaign_id,
  kwm.month,
  kh.keyword_text,
  UPPER(kh.match_type) AS match_type,
  CAST(kwm.impressions AS INT64) AS impressions,
  CAST(kwm.clicks AS INT64) AS clicks,
  ROUND(kwm.cost, 2) AS spend,
  ROUND(SAFE_DIVIDE(kwm.cost, NULLIF(kwm.clicks, 0)), 2) AS cpc,
  CAST(kwm.units AS INT64) AS units,
  ROUND(kwm.units * cg.gp_unit - kwm.cost, 2) AS net_profit,
  ROUND(SAFE_DIVIDE(kwm.units * cg.gp_unit, NULLIF(kwm.cost, 0)), 2) AS net_roas,
  -- TARGET CPC for THIS month = that month's cvr × gp / INTENT floor
  --   = units_7d × gp / (clicks × floor). NULL under 10 clicks (cvr too noisy).
  --   Lets the target track how conversion behavior shifts month to month.
  CASE
    WHEN kwm.clicks < 10 OR cg.gp_unit IS NULL THEN NULL
    ELSE ROUND(SAFE_DIVIDE(kwm.units * cg.gp_unit, kwm.clicks * (SELECT v FROM floor)), 2)
  END AS target_cpc
FROM kwm
LEFT JOIN kh ON kh.keyword_id = kwm.keyword_id
LEFT JOIN camp_gp_final cg ON cg.campaign_id = kwm.campaign_id
-- Only keywords that actually SPENT that month — the month row is a spend/P&L line, so
-- impression-only (0-click, 0-cost) keywords are noise here (they're visible in the Intent
-- keyword panel). Keeps the drill focused on what drove the month's numbers.
WHERE kwm.cost > 0
