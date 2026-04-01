-- =============================================
-- Validation: Keyword product map (Keywords page, Family keyword table)
-- =============================================
-- Purpose: Validate keyword_product_map.json. Compare to dashboard Keywords and Family pages.
-- Source: dashboard/refresh_data.py QUERIES["keyword_product_map.json"] (lines 298-319)
-- Source view: V_EXPERIMENT_TERM_RECOMMENDATIONS (60d window in view)
-- =============================================

SELECT
  r.search_term,
  r.experiment_id,
  r.product_short_name,
  r.hero_asin,
  r.is_hero_match,
  r.action,
  r.reason,
  ROUND(r.ads_spend, 2) as spend_60d,
  r.ads_orders as orders_60d,
  r.ads_clicks as clicks_60d,
  r.ads_impressions as impressions_60d,
  ROUND(SAFE_DIVIDE(r.ads_spend, NULLIF(r.ads_clicks, 0)), 2) as cpc_60d,
  ROUND(r.ads_cvr_pct, 2) as conv_rate_60d,
  ROUND(r.ads_net_roas, 2) as net_roas_60d,
  ROUND(r.market_weekly_orders, 0) as market_volume,
  ROUND(r.your_orders_share_pct, 1) as impression_share
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS` r
ORDER BY r.ads_spend DESC
LIMIT 2000;
