-- =============================================
-- V_RUN_UNCHANGED — the row-grain drill behind V_RUN_SUMMARY's UNCHANGED strip (Phase 6 Task 7).
-- Spec: architecture/WEEKLY_RUN_UX.md. Same population, same class labels (no-drift: both read
-- FACT_KEYWORD_STATE and today's instruction keys), one row per uninstructed keyword with the
-- state machine's own reason sentence — "unchanged, and why" at a glance.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_RUN_UNCHANGED` AS
WITH instructed AS (
  SELECT DISTINCT campaign_id, COALESCE(keyword_id, '') AS kid
  FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`
)
SELECT
  ks.campaign_id, ks.keyword_id, ks.campaign_name, ks.family, ks.target_text, ks.match_type,
  ks.channel, ks.current_bid, ks.state, ks.owner_engine,
  CASE ks.state
    WHEN 'WINNER' THEN 'winners holding'
    WHEN 'PACED_WINNER' THEN 'winners holding'
    WHEN 'TRIAL' THEN 'trial — gathering evidence'
    WHEN 'PARKED' THEN 'parked at minimum bid'
    WHEN 'DEAD' THEN 'tested losers (closed)'
    -- v27.103 bar/SE ladder states (LOSER_BLEED kept for safety; superseded by the ladder);
    -- v27.104: FLOOR_PROBATION added, LOSER now means "probation at the floor elapsed"
    WHEN 'AT_BAR' THEN 'at their family bar — holding within noise'
    WHEN 'REPRICE' THEN 'priced above their record — in the reprice book'
    WHEN 'FLOOR_PROBATION' THEN 'on probation at their floor — re-judged once clicks settle there'
    WHEN 'LOSER' THEN 'failed at their floor after probation — kill candidates (reprice book)'
    WHEN 'LAUNCH_CONTAINED' THEN 'launch — contained, never judged on profit'
    WHEN 'LOSER_BLEED' THEN 'proven losers still spending'
    WHEN 'REVIVED_SETTLING' THEN 'revived — waiting for final sales data'
    WHEN 'PENDING_SETTLE' THEN 'just parked — verdict when sales data completes'
    ELSE LOWER(ks.state) END AS class,
  ks.settled_clk90, ks.settled_roas90,
  -- record_class, v27.103: BAR-RELATIVE (A6). GOOD = the record clears the keyword's own family
  -- bar (FACT_KEYWORD_STATE.family_bar, COALESCEd 1.0 by the SP); MID keeps the engines' 0.6
  -- catastrophic RATIO, now relative to the bar. Published so the dashboard colors by class
  -- instead of re-inventing thresholds in React (feedback_all_logic_in_backend).
  CASE WHEN ks.settled_roas90 >= ks.family_bar THEN 'GOOD'
       WHEN ks.settled_roas90 >= 0.6 * ks.family_bar THEN 'MID'
       WHEN ks.settled_roas90 IS NOT NULL THEN 'BAD'
       ELSE 'NONE' END AS record_class,
  ks.next_check_date, ks.next_check_what,
  ks.state_reason AS why_short
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
LEFT JOIN instructed i
  ON i.campaign_id = ks.campaign_id AND i.kid = COALESCE(ks.keyword_id, '')
WHERE i.campaign_id IS NULL;
