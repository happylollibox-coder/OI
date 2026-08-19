-- =============================================
-- V_SEASON_PEAK_GATE — THE season gate, and the only place its predicate is written.
--
-- One row per DIM_US_HOLIDAYS occurrence that is ACTIVE TODAY. Zero rows = off peak.
--
-- v27.49 (Ori 2026-08-12): the gate missed Back to School and Halloween TWICE over — they are
-- category 'back_to_school'/'seasonal' (not in the old IN-list) AND they carry cooldown_end IS
-- NULL, so the BETWEEN was NULL too. Verified live on a BTS peak day: in_peak read FALSE while a
-- Back-to-School campaign was being budget-CUT, and MINT-SP/BROAD (Back to School) ran 111% of
-- budget capped 6 of 7 days. Both fixes are needed; either alone still excludes BTS.
--
-- v27.50 (2026-08-12): extracted from V_KEYWORD_LIFT's inline `season` CTE so that the gate and
-- the occurrence resolver cannot drift apart. Consumers:
--   * V_KEYWORD_LIFT.season  -> SELECT COUNT(*) > 0 AS in_peak FROM here
--   * V_PEAK_WINDOW_RULE.own -> the same rows, ordered by precedence, LIMIT 1
--
-- WHY THIS IS ITS OWN VIEW AND NOT PART OF V_PEAK_WINDOW_RULE: V_KEYWORD_LIFT expands its
-- `season` CTE about thirty times (every `(SELECT IF(in_peak, ...) FROM season)` site: low_cap,
-- the exploration allowance, probe slots, the budget floor, the click bars). Each reference
-- re-plans the CTE body. Pointing those thirty sites at the full rule view — which also resolves
-- the occurrence type and joins the evidence table — exceeded BigQuery's planner
-- ("Not enough resources for query planning - too many subqueries"). This view is a single
-- filtered scan of a ~40-row table, which is exactly what the v27.49 inline expression cost.
-- KEEP IT TRIVIAL. Do not add joins, aggregates or subqueries here.
--
-- NOT YET a consumer, but should be (SOP architecture/PEAK_WINDOW_RULE.md §6.3):
-- V_KEYWORD_GUARD:66 and V_OOB_KEYWORD:257 still run the PRE-v27.49 predicate
-- (category IN ('gift_season','prime_event'), no COALESCE on cooldown_end) and therefore read
-- in_peak = FALSE today while V_KEYWORD_LIFT reads TRUE. Out of scope for v27.50 because
-- fixing it moves bids, not windows.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SEASON_PEAK_GATE` AS
SELECT
  holiday_name,
  category,
  holiday_date,
  boost_start,
  COALESCE(cooldown_end, DATE_ADD(holiday_date, INTERVAL 3 DAY)) AS win_end
FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
WHERE category IN ('gift_season', 'prime_event', 'back_to_school', 'seasonal')
  AND CURRENT_DATE('America/New_York')
      BETWEEN boost_start AND COALESCE(cooldown_end, DATE_ADD(holiday_date, INTERVAL 3 DAY));
