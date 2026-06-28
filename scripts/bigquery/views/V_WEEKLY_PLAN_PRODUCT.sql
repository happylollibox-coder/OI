-- V_WEEKLY_PLAN_PRODUCT — per-product rollup of the weekly plan (Coacher D).
-- One row per product x week x horizon. The This Week page reads this directly so the
-- surface does zero aggregation (all logic in backend). Outcome is purpose-specific:
--   forward_ads_net    = $ from profit-SCALE cells (net_per_dollar x planned_spend),
--                        ads-attributed only (no organic halo) — the plan's forward dollar bet.
--   probe_map_clicks   = click target summed over MAP/PROBE cells (those measure clicks, not $).
-- DEFEND/CUT/HOLD cells carry no single scalar (measured by TOS / spend-down / hold).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_PRODUCT` AS
SELECT
  parent_name,
  CAST(week_start AS STRING) AS week_start,
  horizon,
  COUNT(*) AS cells,
  COUNTIF(purpose = 'SCALE') AS scale_cells,
  ROUND(SUM(planned_spend), 2) AS planned_spend,
  ROUND(SUM(IF(purpose = 'SCALE', expected_value, 0)), 2) AS forward_ads_net,
  CAST(ROUND(SUM(IF(purpose IN ('MAP', 'PROBE'), expected_value, 0)), 0) AS INT64) AS probe_map_clicks,
  STRING_AGG(DISTINCT LOWER(purpose), ' · ' ORDER BY LOWER(purpose)) AS purposes
FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
GROUP BY parent_name, week_start, horizon
