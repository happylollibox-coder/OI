-- V_COACH_APPLY — deduped, ready-to-upload apply set (prepare-only; Ori uploads the bulksheet). Coacher F.
-- One row per entity to change, so the Amazon bulksheet can't be rejected for "Duplicate Id".
-- v1 = keyword bid changes deduped to one row per keyword_id (V_ADS_COACH is search-term grain → ~104x fan-out).
-- Backend (per all-logic-in-backend); the frontend formats these rows into the Amazon Bulksheet XLSX.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COACH_APPLY` AS
WITH bid AS (
  SELECT
    keyword_id, ANY_VALUE(campaign_id) AS campaign_id,
    parent_name,
    -- one decision per keyword: take the highest-priority row's action + bid (keyword-grain logic is
    -- repeated across search-term slices; ORDER makes the pick deterministic and avoids contradictions)
    ARRAY_AGG(STRUCT(target_action, recommended_bid, current_bid, bid_change_pct)
              ORDER BY priority_score DESC, ABS(bid_change_pct) DESC LIMIT 1)[OFFSET(0)] AS pick,
    MAX(priority_score) AS priority_score
  FROM `onyga-482313.OI.V_ADS_COACH`
  WHERE target_action IN ('INCREASE_BID', 'REDUCE_BID', 'PROBE')
    AND keyword_id IS NOT NULL AND recommended_bid IS NOT NULL
  GROUP BY keyword_id, parent_name
)
SELECT
  'KEYWORD_BID' AS entity_type,
  keyword_id    AS entity_id,
  campaign_id,
  parent_name,
  'Update'      AS operation,
  pick.current_bid     AS current_bid,
  ROUND(pick.recommended_bid, 2) AS new_bid,
  ROUND(pick.bid_change_pct, 0)  AS bid_change_pct,
  pick.target_action   AS source_action,
  priority_score
FROM bid
