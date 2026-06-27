-- V_STRATEGY_GAPS — cells active in ads but not steering (missing profile or WEAK).
-- Drives borrow (Component B) and probe (Component C). Coacher sub-project C.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_STRATEGY_GAPS` AS
WITH cell AS (             -- aggregate live keyword rows to the profile cell grain
  SELECT
    parent_name, season, match_type, intent_class,
    COUNT(DISTINCT keyword_id)                                   AS keyword_count,
    COUNTIF(COALESCE(no_traffic_rate, 0) >= 0.8)                 AS starved_keyword_count,
    ROUND(SUM(COALESCE(ads_spend_8w, 0)), 2)                     AS spend_at_risk,
    ROUND(SUM(COALESCE(sqp_amazon_search_volume_8w, 0)), 0)      AS demand_signal
  FROM `onyga-482313.OI.V_ADS_COACH_DATA`
  WHERE keyword_id IS NOT NULL
    AND season IS NOT NULL AND match_type IS NOT NULL AND intent_class IS NOT NULL
  GROUP BY 1,2,3,4
),
prof AS (
  SELECT parent_name, season, match_type, intent_class, source, confidence
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
),
gaps AS (
  SELECT
    c.parent_name, c.season, c.match_type, c.intent_class,
    CASE WHEN p.parent_name IS NULL THEN 'MISSING' ELSE 'WEAK' END AS gap_type,
    c.spend_at_risk, c.keyword_count, c.starved_keyword_count, c.demand_signal,
    -- a donor exists if any CONCLUSIVE cell shares the intent AND (same parent OR same match) —
    -- the reachable set of the borrow ladder (steps 1-4)
    EXISTS (SELECT 1 FROM prof d WHERE d.confidence='CONCLUSIVE'
              AND d.intent_class = c.intent_class
              AND (d.parent_name = c.parent_name OR d.match_type = c.match_type)) AS has_borrow_donor,
    (c.starved_keyword_count > 0 AND c.demand_signal >= 100) AS is_probeable_raw
  FROM cell c
  LEFT JOIN prof p USING (parent_name, season, match_type, intent_class)
  -- only surface cells that do NOT steer: missing, or present-but-WEAK-and-not-manual/borrowed
  WHERE p.parent_name IS NULL
     OR (COALESCE(p.source,'DERIVED') NOT IN ('MANUAL','BORROWED') AND p.confidence = 'WEAK')
)
SELECT *,
  CASE WHEN has_borrow_donor THEN 'BORROW'
       WHEN is_probeable_raw THEN 'PROBE'
       ELSE 'NONE' END AS suggested_resolution
FROM gaps
