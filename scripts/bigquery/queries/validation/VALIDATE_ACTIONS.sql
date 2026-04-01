-- =============================================
-- Validation: Actions table (action recommendations)
-- =============================================
-- Purpose: Validate actions.json. Compare to dashboard Actions page.
-- Source: dashboard/refresh_data.py QUERIES["actions.json"] (lines 176-206)
-- Source view: V_EXPERIMENT_TERM_RECOMMENDATIONS (no date filter in current query)
-- =============================================

SELECT
  action, ads_signal, reason,
  search_term, experiment_id,
  product_short_name, hero_asin, is_hero_match,
  ROUND(ads_spend, 2) as spend,
  ads_orders as orders,
  ads_clicks as clicks,
  ROUND(SAFE_DIVIDE(ads_spend, NULLIF(ads_clicks, 0)), 2) as cpc,
  ROUND(ads_cvr_pct, 2) as conv_rate,
  ROUND(ads_net_roas, 2) as net_roas,
  ROUND(margin_per_unit, 2) as margin_per_unit,
  ROUND(market_weekly_orders, 0) as market_volume,
  ROUND(your_orders_share_pct, 1) as impression_share,
  priority_score,
  strategy_id
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE action NOT IN ('KEEP', 'MONITOR')
ORDER BY
  CASE action
    WHEN 'STOP' THEN 1
    WHEN 'REDUCE_BID' THEN 2
    WHEN 'PROMOTE_TO_EXACT' THEN 3
    WHEN 'START' THEN 4
    WHEN 'BOOST' THEN 5
    ELSE 6
  END,
  ads_spend DESC;
