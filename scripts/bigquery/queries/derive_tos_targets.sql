-- derive_tos_targets.sql — per (parent×season×match_type×intent) cell, the 75th-pct top-of-search share
-- among net-profitable keyword-days, written to DE_PRODUCT_STRATEGY_PROFILE.tos_target_pct (DERIVED rows only).
-- Low-end floor: a derived target below TOS_FLOOR_PCT (3%) means the cell's own winners never reached a
-- meaningful top-of-search position, so bidding toward it just buys buried impressions (spec §8). We NULL
-- those cells — the TOS bid branches in V_ADS_COACH gate on `tos_target_pct IS NOT NULL`, so a NULL simply
-- opts the cell out of TOS-driven bidding (e.g. Lollibox GENERIC cells whose p75 is ~0.1%).
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
  ),
  agg AS (
    SELECT parent_name AS parent, season, match_type, intent_class,
           ROUND(APPROX_QUANTILES(tos_share, 100)[OFFSET(75)], 1) AS tos_p75
    FROM cells GROUP BY 1,2,3,4
  )
  -- apply the 3% floor: below it, NULL the target so the cell opts out of TOS bidding
  SELECT parent, season, match_type, intent_class,
         IF(tos_p75 < 3.0, NULL, tos_p75) AS tos_p75
  FROM agg
) s
WHERE p.parent_name = s.parent AND p.season = s.season
  AND p.match_type = s.match_type AND p.intent_class = s.intent_class
  AND COALESCE(p.source,'DERIVED') != 'MANUAL';
