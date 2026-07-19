-- V_COACH_CAMPAIGN_BUDGET — campaign-grain budget recommendations per family (Coacher F, budget apply set).
-- V_ADS_COACH is search-term grain; this dedupes to ONE row per campaign with its budget decision so the
-- Weekly Run inline Budget phase (and any bulksheet budget rows) can read it directly.
-- Backend (all-logic-in-backend); is_change flags the rows that are an actual budget move.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COACH_CAMPAIGN_BUDGET` AS
WITH camp AS (
  SELECT
    parent_name,
    campaign_id,
    ANY_VALUE(campaign_name)       AS campaign_name,
    ANY_VALUE(campaign_type)       AS campaign_type,
    ANY_VALUE(budget_action)       AS budget_action,
    ANY_VALUE(current_budget)      AS current_budget,
    ANY_VALUE(recommended_budget)  AS recommended_budget,
    ANY_VALUE(camp_budget_util_pct) AS util_pct,
    -- the engine's actual budget driver: effective ROAS (the number the GUARDIAN/BLITZ decision keys on),
    -- new-campaign flag, and the coach mode — so the Weekly Run can explain WHY a budget moves
    ANY_VALUE(camp_effective_roas) AS effective_roas,
    ANY_VALUE(is_new_campaign)     AS is_new_campaign,
    ANY_VALUE(coach_mode)          AS coach_mode
  FROM `onyga-482313.OI.V_ADS_COACH`
  WHERE campaign_id IS NOT NULL
    AND budget_action IS NOT NULL
    AND parent_name IS NOT NULL
  GROUP BY parent_name, campaign_id
)
SELECT
  parent_name,
  campaign_id,
  campaign_name,
  campaign_type,
  budget_action,
  ROUND(current_budget, 2)     AS current_budget,
  ROUND(recommended_budget, 2) AS recommended_budget,
  util_pct,
  ROUND(effective_roas, 2)     AS effective_roas,
  is_new_campaign,
  coach_mode,
  -- an actual move: the engine emitted a recommended budget that differs from current
  (recommended_budget IS NOT NULL
    AND current_budget IS NOT NULL
    AND ABS(recommended_budget - current_budget) >= 0.01) AS is_change
FROM camp;
