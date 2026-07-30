-- =============================================
-- V_INTENT_COVERAGE
-- The Phase 0 gate: how much of real ads traffic carries an intent theme.
-- Grain: parent_name x intent_key (with a grand-total row per family, intent_key = NULL).
--
-- Phase 1 (the product x intent CVR curve that sets base bids) does not start until the
-- account-wide classified share of clicks clears 60%. Baseline on 2026-07-24, before this
-- work: 11.1% of ads clicks carried a real occasion via V_SEARCH_TERM_SEGMENT.
--
-- Also the regression surface: if a rule edit in DE_INTENT_THEMES drops coverage or floods a
-- theme, it shows up here first.
--
-- Dependencies: FACT_AMAZON_ADS, V_INTENT_RESOLVED, DIM_PRODUCT
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_COVERAGE` AS

WITH ads AS (
  SELECT
    p.parent_name,
    a.search_term,
    a.Ads_clicks,
    a.Ads_orders,
    a.Ads_cost,
    a.GROSS_PROFIT
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
),

joined AS (
  SELECT ads.*, i.intent_key, i.intent_type
  FROM ads
  LEFT JOIN `onyga-482313.OI.V_INTENT_RESOLVED` i
    ON i.search_term = ads.search_term
)

SELECT
  -- GROUPING SETS puts three different kinds of row in one result. Without this the
  -- genuinely-unclassified bucket (intent_key IS NULL) is indistinguishable from the
  -- rollups, which also carry a NULL intent_key. Always filter on row_type.
  CASE
    WHEN GROUPING(parent_name) = 1 THEN 'ACCOUNT_TOTAL'
    WHEN GROUPING(intent_key) = 1  THEN 'FAMILY_TOTAL'
    WHEN intent_key IS NULL        THEN 'UNCLASSIFIED'
    ELSE 'THEME'
  END                                                           AS row_type,
  parent_name,
  intent_key,
  intent_type,
  COUNT(DISTINCT search_term)                                   AS terms,
  SUM(Ads_clicks)                                               AS clicks,
  SUM(Ads_orders)                                               AS orders,
  ROUND(SUM(Ads_cost), 2)                                       AS cost,
  ROUND(SUM(GROSS_PROFIT), 2)                                   AS gross_profit,
  ROUND(100 * SAFE_DIVIDE(SUM(Ads_orders), SUM(Ads_clicks)), 2) AS cvr_pct,
  ROUND(SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)), 2)         AS cpc,
  ROUND(SAFE_DIVIDE(SUM(GROSS_PROFIT), SUM(Ads_clicks)), 3)     AS gp_per_click,
  -- Share of this family's clicks that this theme accounts for. On the intent_key IS NULL
  -- rollup row (GROUPING SETS grand total) this is 100 by construction; read pct_classified
  -- from the companion column instead.
  ROUND(100 * SAFE_DIVIDE(
    SUM(Ads_clicks),
    SUM(SUM(Ads_clicks)) OVER (PARTITION BY parent_name)), 2)   AS pct_of_family_clicks,
  ROUND(100 * SAFE_DIVIDE(
    SUM(IF(intent_key IS NOT NULL, Ads_clicks, 0)),
    SUM(Ads_clicks)), 2)                                        AS pct_classified
FROM joined
GROUP BY GROUPING SETS ((parent_name, intent_key, intent_type), (parent_name), ());
