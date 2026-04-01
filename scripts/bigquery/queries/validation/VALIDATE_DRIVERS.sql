-- =============================================
-- Validation: Drivers table (top performers, Family page)
-- =============================================
-- Purpose: Validate drivers.json. Compare to dashboard Family DriverTable.
-- Source: dashboard/refresh_data.py QUERIES["drivers.json"] (lines 597-621)
-- Source view: V_EXPERIMENT_TERM_RECOMMENDATIONS
-- =============================================

SELECT
  r.search_term,
  r.product_short_name,
  r.experiment_id,
  r.action,
  ROUND(r.ads_spend, 2) as spend,
  r.ads_orders as orders,
  r.ads_clicks as clicks,
  ROUND(SAFE_DIVIDE(r.ads_spend, NULLIF(r.ads_clicks, 0)), 2) as cpc,
  ROUND(r.ads_cvr_pct, 2) as conv_rate,
  ROUND(r.margin_per_unit, 2) as margin_per_unit,
  ROUND(r.your_orders_share_pct, 1) as impression_share,
  ROUND(r.ads_net_roas, 2) as net_roas,
  CASE
    WHEN p.product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
    WHEN p.product_short_name LIKE '%LolliME%' THEN 'LolliME'
    WHEN p.product_short_name LIKE '%Fresh%' THEN 'Fresh'
    WHEN p.product_short_name LIKE '%Truth%' OR p.product_short_name LIKE '%Bottle%' THEN 'Bottle'
    ELSE p.product_short_name
  END as product_type
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS` r
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON r.hero_asin = p.asin
ORDER BY r.ads_spend DESC
LIMIT 2000;
