-- =============================================
-- V_COVERAGE_INTENT
-- Per (family x intent) "is this intent suggested?" flag for the coverage cockpit's
-- keyword panel — lets the frontend split suggested vs not-suggested intents.
-- Grain: one row per (parent_name, intent_key).
-- Built from V_INTENT_KEYWORDS (relevant keywords only), rolled to the intent.
--
-- suggested rule (Ori 2026-07-22 — "profit, else research fit"):
--   running intent (spend > 0)  -> suggested only if profitable: wtd_net_roas >= INTENT floor
--   not-yet-running intent       -> TRUE (research routed keywords here => research-recommended)
-- INTENT floor = DE_COACH_THRESHOLDS PROFITABLE_ROAS / strategy INTENT (= 1.1), matching
-- the GUARDIAN per-strategy net-ROAS floors.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_INTENT` AS
SELECT
  parent_name,
  intent_key,
  ANY_VALUE(label) AS label,
  COUNT(DISTINCT query_text) AS n_kws,
  ROUND(SUM(ads_spend)) AS spend,
  ROUND(SAFE_DIVIDE(SUM(ads_net_roas * ads_spend), NULLIF(SUM(ads_spend), 0)), 2) AS wtd_net_roas,
  CASE
    WHEN SUM(ads_spend) > 0
      THEN ROUND(SAFE_DIVIDE(SUM(ads_net_roas * ads_spend), NULLIF(SUM(ads_spend), 0)), 2)
           >= (SELECT MAX(CAST(threshold_value AS FLOAT64))
               FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
               WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id = 'INTENT')
    ELSE TRUE
  END AS suggested
FROM `onyga-482313.OI.V_INTENT_KEYWORDS`
WHERE is_relevant AND parent_name IS NOT NULL AND intent_key IS NOT NULL
GROUP BY parent_name, intent_key;
