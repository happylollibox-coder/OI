-- V_ADS_NET_CORRECTED — ad gross profit with COGS costed by the PRODUCT ACTUALLY SOLD (identified by sale
-- price via V_PRICE_COST_TIER), not the advertised product FACT charges today.
--
-- WHY: FACT_AMAZON_ADS.GROSS_PROFIT charges the advertised ASIN's cost, but ~80% of ad-attributed units are
-- a different product and ~8-12% a different PRICE TIER (a $54 box ad drives a $14 ball sale) — those get the
-- wrong COGS and fabricate per-target losses that mislead the coacher. Corrected per-unit cost = price-tier
-- cost when the sale price matches a tier, else the current (advertised) cost, so unmatched prices (deep
-- coupon/bundle, ~4% of units) are left unchanged.
--
-- ROW-LEVEL (one row per FACT row, NOT pre-aggregated) so consumers can SUM in a single step — a pre-grouped
-- view can't be re-aggregated in BigQuery. Exposes gross_profit_now beside gross_profit_corrected so the card
-- can show current vs corrected net ROAS side by side, non-destructively, before anything feeds decisions.
-- Grain: same as FACT_AMAZON_ADS (date, campaign, ad_group, keyword, search_term). Spec: [[project_ads_cogs_price_imputation]].
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_NET_CORRECTED` AS
SELECT
  f.date,
  CAST(f.campaign_id AS STRING) AS campaign_id,
  CAST(f.ad_group_id AS STRING) AS ad_group_id,
  CAST(f.keyword_id  AS STRING) AS keyword_id,
  f.search_term,
  f.Ads_cost  AS spend,
  f.Ads_sales AS sales,
  f.Ads_units AS units,
  f.GROSS_PROFIT AS gross_profit_now,
  ROUND(f.Ads_sales - COALESCE(t.tier_cost, f.TOTAL_COST_PER_UNIT) * f.Ads_units, 4) AS gross_profit_corrected,
  COALESCE(t.tier_cost, f.TOTAL_COST_PER_UNIT) AS corrected_cost_per_unit,
  (t.tier_cost IS NOT NULL) AS price_matched
FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
-- join the MATERIALIZED tier table (not the view) — a view-with-aggregation inlines and makes any
-- downstream re-aggregation of this view fail with "aggregations of aggregations". T_PRICE_COST_TIER is
-- refreshed from V_PRICE_COST_TIER (small; fold into SP_REFRESH_CUBE_TABLES).
LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` t
  ON f.Ads_units > 0 AND t.unit_price = ROUND(SAFE_DIVIDE(f.Ads_sales, f.Ads_units), 2)
WHERE f.keyword_id IS NOT NULL;
