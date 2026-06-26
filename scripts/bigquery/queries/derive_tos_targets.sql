-- derive_tos_targets.sql — per (parent×season×match_type×intent) cell, the 75th-pct top-of-search share
-- among net-profitable keyword-days, written to DE_PRODUCT_STRATEGY_PROFILE.tos_target_pct (DERIVED rows only).
UPDATE `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` p
SET p.tos_target_pct = s.tos_p75, p.updated_at = CURRENT_TIMESTAMP()
FROM (
  WITH cal AS (
    SELECT d AS date,
      IF(MAX(CASE WHEN d BETWEEN h.boost_start AND h.cooldown_start THEN 1 END)=1,'PEAK','OFF') AS season
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE('2025-09-23'), CURRENT_DATE('America/Los_Angeles'))) d
    LEFT JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON d BETWEEN h.boost_start AND h.cooldown_start
    GROUP BY d
  ),
  cells AS (
    SELECT kd.parent_name, cal.season, kd.match_type,
           COALESCE(ic.intent_class,'GENERIC') AS intent_class,
           kd.tos_share, kd.impressions
    FROM `onyga-482313.OI.V_KEYWORD_DAILY` kd
    JOIN cal ON cal.date = kd.date
    LEFT JOIN `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` ic
      ON ic.parent_name = kd.parent_name AND ic.keyword_text = LOWER(kd.keyword_text)
    WHERE kd.net_proxy > 0 AND kd.impressions > 0 AND kd.match_type IN ('BROAD','EXACT','PHRASE')
  )
  SELECT parent_name AS parent, season, match_type, intent_class,
         ROUND(APPROX_QUANTILES(tos_share, 100)[OFFSET(75)], 1) AS tos_p75
  FROM cells GROUP BY 1,2,3,4
) s
WHERE p.parent_name = s.parent AND p.season = s.season
  AND p.match_type = s.match_type AND p.intent_class = s.intent_class
  AND COALESCE(p.source,'DERIVED') != 'MANUAL';
