-- =============================================
-- V_RUN_SUMMARY — the Weekly Run front page as one small-table query (2026-08-16, Phase 6 Task 2).
-- Spec: architecture/WEEKLY_RUN_UX.md. One row per summary cell; three sections:
--   CHANGES   today's GO instructions by direction ($/day on BUDGET moves ONLY — bid-level $/day
--             would be invented precision)
--   HELD      what the gate excluded / flagged, by class
--   UNCHANGED the rest of the account, from the STATE MACHINE (FACT_KEYWORD_STATE supersedes the
--             plan's interim guard-based taxonomy — built the day before this view)
-- Reads ONLY snapshot tables. Target: renders in seconds.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_RUN_SUMMARY` AS
WITH pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
changes AS (
  SELECT 'CHANGES' AS section,
    -- v27.72: NEGATE before the bid arms — a negate has NULL values, and NULL < NULL is NULL,
    -- so without its own arm every block lands in the ELSE and inflates "bid raises"
    CASE WHEN lever = 'NEGATE' THEN 'search terms blocked'
         WHEN lever = 'BUDGET' AND suggested_budget < current_budget THEN 'budget cuts'
         WHEN lever = 'BUDGET' THEN 'budget raises'
         WHEN grain = 'REVIVE' THEN 'revivals'
         WHEN suggested_bid < current_bid THEN 'bid cuts'
         ELSE 'bid raises' END AS label,
    COUNT(*) AS n,
    ROUND(SUM(IF(lever = 'BUDGET', suggested_budget - current_budget, 0)), 2) AS dollars_per_day,
    CAST(NULL AS STRING) AS detail
  FROM pf WHERE verdict = 'GO'
  GROUP BY 2
),
held AS (
  SELECT 'HELD' AS section,
    -- class label: strip the per-row numbers so REVIEW rows GROUP (the '(' split) — the row
    -- detail keeps one full example reason
    CONCAT(LOWER(verdict), ' — ',
           COALESCE(SPLIT(SPLIT(verdict_reason, ' (')[SAFE_OFFSET(0)], ' — ')[SAFE_OFFSET(0)], 'other')) AS label,
    COUNT(*) AS n, CAST(NULL AS FLOAT64) AS dollars_per_day,
    ANY_VALUE(verdict_reason) AS detail
  FROM pf WHERE verdict != 'GO'
  GROUP BY 2
),
instructed AS (SELECT DISTINCT campaign_id, COALESCE(keyword_id, '') AS kid FROM pf),
unchanged AS (
  SELECT 'UNCHANGED' AS section,
    CASE ks.state
      WHEN 'WINNER' THEN 'winners holding'
      WHEN 'PACED_WINNER' THEN 'winners holding'   -- paced ones with no live instruction today
      WHEN 'TRIAL' THEN 'trial — gathering evidence'
      WHEN 'PARKED' THEN 'parked at minimum bid'
      WHEN 'DEAD' THEN 'tested losers (closed)'
      -- v27.103 bar/SE ladder states (LOSER_BLEED kept for safety; superseded by the ladder)
      WHEN 'AT_BAR' THEN 'at their family bar — holding within noise'
      WHEN 'REPRICE' THEN 'priced above their record — in the reprice book'
      WHEN 'LOSER' THEN 'failed at their price — kill candidates (reprice book)'
      WHEN 'LAUNCH_CONTAINED' THEN 'launch — contained, never judged on profit'
      WHEN 'LOSER_BLEED' THEN 'proven losers still spending'
      WHEN 'REVIVED_SETTLING' THEN 'revived — waiting for final sales data'
      WHEN 'PENDING_SETTLE' THEN 'just parked — verdict when sales data completes'
      ELSE LOWER(ks.state) END AS label,
    COUNT(*) AS n, CAST(NULL AS FLOAT64) AS dollars_per_day,
    ANY_VALUE(ks.next_check_what) AS detail
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
  LEFT JOIN instructed i
    ON i.campaign_id = ks.campaign_id AND i.kid = COALESCE(ks.keyword_id, '')
  WHERE i.campaign_id IS NULL   -- anti-join by equality only
  GROUP BY 2
)
SELECT * FROM changes UNION ALL SELECT * FROM held UNION ALL SELECT * FROM unchanged;
