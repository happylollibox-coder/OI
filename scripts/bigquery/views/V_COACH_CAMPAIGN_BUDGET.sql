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
    ANY_VALUE(coach_mode)          AS coach_mode,
    -- v27.56 launch exemption (V_ADS_COACH.scored_exempt): budget_action reads LAUNCH_EXEMPT_HOLD
    -- where a ROAS-driven cut was blocked, and recommended_budget is deliberately NULL on those rows
    -- so is_change below can never queue the suppressed cut. The blocked decision is kept HERE for
    -- display only. All campaign-constant per campaign_id → ANY_VALUE is safe (no ratio is formed
    -- from two ANY_VALUEs).
    ANY_VALUE(launch_exempt)            AS launch_exempt,
    ANY_VALUE(launch_exempt_until)      AS launch_exempt_until,
    ANY_VALUE(budget_action_suppressed) AS budget_action_suppressed,
    ANY_VALUE(budget_suppressed_to)     AS budget_suppressed_to,
    -- TRUE where a DOWNWARD budget number was published behind a BUDGET_OK label (the 3-day
    -- cooldown masks the action but not the number) and the exemption removed it.
    ANY_VALUE(launch_down_rec_blocked)  AS launch_down_rec_blocked
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
  -- v27.66 (engine-finalization Task 1.7, 2026-08-16): THE LABEL MAY NOT CONTRADICT THE NUMBER.
  -- V_ADS_COACH's cooldown/mode branches publish budget_action='BUDGET_OK' while recommended_budget
  -- still carries a live move (the 3-day cooldown and the <14d new-campaign branch mask the ACTION
  -- string but not the NUMBER) — and is_change below keys on the NUMBER, so the move exports to
  -- the apply set behind a green label. Measured at fix time: 26 campaigns, $501.31/day of cuts +
  -- $100.25/day of raises labeled "OK" (the finding recorded 16/$260 on 2026-08-13 — it had
  -- doubled in three days). Task 1.5's doctrine, same week: THE VERB MUST MATCH THE MOVE. The
  -- exporting row now names its direction; the names are chosen so V_WEEKLY_RUN_CAMPAIGN's
  -- existing LIKE '%DECREASE%'/'%INCREASE%' strategy classifier catches them with zero changes.
  -- The 0.01 threshold is is_change's own, so the label and the export can never flip apart.
  CASE
    WHEN budget_action = 'BUDGET_OK' AND recommended_budget IS NOT NULL AND current_budget IS NOT NULL
         AND recommended_budget <= current_budget - 0.01 THEN 'BUDGET_DECREASE_PENDING'
    WHEN budget_action = 'BUDGET_OK' AND recommended_budget IS NOT NULL AND current_budget IS NOT NULL
         AND recommended_budget >= current_budget + 0.01 THEN 'BUDGET_INCREASE_PENDING'
    ELSE budget_action END AS budget_action,
  -- the honest sentence for any panel that wants it — why the label was overridden
  CASE
    WHEN budget_action = 'BUDGET_OK' AND recommended_budget IS NOT NULL AND current_budget IS NOT NULL
         AND ABS(recommended_budget - current_budget) >= 0.01
      THEN CONCAT('the coach label read BUDGET_OK (cooldown/mode mask) but a live budget move is published: $',
                  FORMAT('%.2f', current_budget), ' → $', FORMAT('%.2f', recommended_budget),
                  ' — the label now names the move; the number was always in the apply set')
    ELSE NULL END AS budget_action_note,
  ROUND(current_budget, 2)     AS current_budget,
  ROUND(recommended_budget, 2) AS recommended_budget,
  util_pct,
  ROUND(effective_roas, 2)     AS effective_roas,
  is_new_campaign,
  coach_mode,
  launch_exempt,
  launch_exempt_until,
  budget_action_suppressed,                          -- what the coach would have done (display only)
  ROUND(budget_suppressed_to, 2) AS budget_suppressed_to,
  launch_down_rec_blocked,
  -- an actual move: the engine emitted a recommended budget that differs from current.
  -- A launch-exempt hold carries recommended_budget = NULL by construction, so is_change is FALSE
  -- and a suppressed cut can never reach the budget apply set / bulksheet.
  (recommended_budget IS NOT NULL
    AND current_budget IS NOT NULL
    AND ABS(recommended_budget - current_budget) >= 0.01) AS is_change
FROM camp;
