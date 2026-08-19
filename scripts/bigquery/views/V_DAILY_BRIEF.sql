-- =============================================
-- V_DAILY_BRIEF — one query answers Ori's three daily questions (2026-08-15).
-- Spec: architecture/DAILY_BRIEF.md.
--
-- (Ori 2026-08-15): "i can ask you daily what was planned, what actually happened and what are
-- your action items. the purpose is to make it better. meaning if after a change it became worse
-- this is not good."
--
-- FOUR SECTIONS, one uniform row shape, so the whole brief is SELECT * ORDER BY section:
--   PLANNED      — the latest FACT_ENGINE_PROPOSALS snapshot: what the engine wants done today.
--   HAPPENED     — changes APPLIED in the last 48h, split status=planned (the engine proposed it
--                  on the day it was applied) / unplanned (manual, or the engine never said it —
--                  the manual-divergence doctrine's raw material).
--   VERDICT_NEW  — scorecard verdicts that became READABLE in the last 3 days. THE LAG IS THE
--                  INSTRUMENT: a change is judged at T+14 (SB T+21), never earlier — an early read
--                  systematically under-reads your own change and manufactures churn
--                  (V_CHANGE_SCORECARD header). So "what actually happened" arrives on a delay,
--                  by design, and this section is where it lands the morning it is finally honest.
--   ACTION_ITEM  — verdicts that DEMAND a hand: REVERSED (restore the pre-change value, NEVER
--                  lower — remedy_value is the number) still unrestored, from the last 14 days of
--                  newly-readable grades. "if after a change it became worse this is not good" —
--                  this section is that sentence, mechanized.
--
-- PLANNER NOTE: V_CHANGE_SCORECARD is a ceiling view; FACT_ENGINE_PROPOSALS and the change log
-- are cheap. The scorecard subtree appears in two UNION arms — kept lean (no further joins on
-- those arms). If this view ever hits the planner, snapshot the scorecard the same way the guard
-- is snapshotted and point the two arms at the table.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_DAILY_BRIEF` AS
WITH latest AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
),

planned AS (
  SELECT
    'PLANNED' AS section, 1 AS section_rank,
    p.engine AS source, p.campaign_name, p.target_text AS item, p.action,
    COALESCE(p.current_bid, p.current_budget) AS from_value,
    COALESCE(p.suggested_bid, p.suggested_budget) AS to_value,
    p.grain AS status,
    p.reason AS detail,
    p.campaign_id, p.keyword_id
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` p, latest
  WHERE p.snapshot_date = latest.d
),

happened AS (
  -- the change log carries no campaign NAME — join the dim (cheap, current row only)
  SELECT
    'HAPPENED' AS section, 2 AS section_rank,
    a.source, dc.campaign_name, a.targeting AS item, a.action,
    COALESCE(a.old_bid, a.old_budget) AS from_value,
    COALESCE(a.new_bid, a.new_budget) AS to_value,
    -- planned = the engine proposed THIS key on the day it was applied
    IF(p.campaign_id IS NOT NULL, 'planned', 'unplanned') AS status,
    CONCAT('applied ', CAST(DATE(a.applied_at, 'America/Los_Angeles') AS STRING),
           IF(p.campaign_id IS NOT NULL,
              CONCAT(' — engine (', p.engine, ') proposed ',
                     CAST(COALESCE(p.suggested_bid, p.suggested_budget) AS STRING)),
              ' — no engine proposal that day')) AS detail,
    CAST(a.campaign_id AS STRING) AS campaign_id, CAST(a.keyword_id AS STRING) AS keyword_id
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` a
  LEFT JOIN `onyga-482313.OI.FACT_ENGINE_PROPOSALS` p
    ON p.snapshot_date = DATE(a.applied_at, 'America/Los_Angeles')
   AND p.campaign_id = CAST(a.campaign_id AS STRING)
   AND COALESCE(p.keyword_id, '') = COALESCE(CAST(a.keyword_id AS STRING), '')
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = CAST(a.campaign_id AS STRING)
  WHERE a.applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
),

verdict_new AS (
  SELECT
    'VERDICT_NEW' AS section, 3 AS section_rank,
    CONCAT(s.source, ' ', s.coach_mode) AS source, s.campaign_name,
    COALESCE(s.targeting, s.search_term) AS item, s.action,
    SAFE_CAST(s.old_value AS FLOAT64) AS from_value,
    SAFE_CAST(s.new_value AS FLOAT64) AS to_value,
    s.verdict AS status,
    CONCAT(s.verdict_reason, ' · window GP-ROAS ',
           CAST(ROUND(COALESCE(s.win_gp_roas, 0), 2) AS STRING),
           IF(s.prior_available, CONCAT(' vs own prior ', CAST(ROUND(s.prior_gp_roas, 2) AS STRING)), ' (no prior)')) AS detail,
    CAST(s.campaign_id AS STRING) AS campaign_id, CAST(s.keyword_id AS STRING) AS keyword_id
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD` s
  WHERE s.read_gate_date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
                             AND CURRENT_DATE('America/Los_Angeles')
),

action_items AS (
  -- REVERSED = it became worse AND fell below its own record. Remedy is ALWAYS "restore the
  -- pre-change value" (remedy_value), never a further cut — the scorecard never punishes twice.
  --
  -- v2 (2026-08-15, same day it was born — the FIRST upload attempt caught this): a remedy is only
  -- a RESTORE while the graded change is still the STANDING value. The v1 filter used
  -- n_later_changes = 0, which counts later changes INSIDE THE GRADING WINDOW only — 25 of the
  -- first 27 "restores" had been re-decided since (BALL Mint loose-match: graded 0.69->0.55 on
  -- Jul 22, then FIVE more changes through Aug 9, live at $0.34 — "restore to $0.69" would stomp
  -- the newer ladder mid-settle, whose own verdict is not readable until Aug 23). Three guards:
  --   1. next_change_date IS NULL — no later change at ALL, not just in-window;
  --   2. LIVE PARITY — the config's current value must equal the graded new_value (+-0.011);
  --      an unlogged drift means the world moved without the log, which is its own finding;
  --   3. CONFLICT FLAG — if TODAY's proposal snapshot has any engine instructing this key, the
  --      row demotes to REVIEW naming the conflict (single-home: a live engine outranks a
  --      scorecard remedy; low stock outranks everything).
  SELECT
    'ACTION_ITEM' AS section, 4 AS section_rank,
    'SCORECARD' AS source, s.campaign_name,
    COALESCE(s.targeting, s.search_term) AS item, s.action,
    SAFE_CAST(s.new_value AS FLOAT64) AS from_value,   -- where it sits now (verified live below)
    SAFE_CAST(s.remedy_value AS FLOAT64) AS to_value,  -- restore to this
    IF(pr.campaign_id IS NOT NULL, 'REVIEW', 'RESTORE') AS status,
    CONCAT('REVERSED on settled evidence — restore ', s.value_kind, ' to ',
           CAST(s.remedy_value AS STRING), ' (was changed ',
           CAST(s.change_date AS STRING), '; ', s.verdict_reason, ')',
           IF(pr.campaign_id IS NOT NULL,
              CONCAT(' · CONFLICT: ', pr.engine, ' proposes ', pr.action, ' ',
                     CAST(COALESCE(pr.suggested_bid, pr.suggested_budget) AS STRING),
                     ' today — the live engine outranks the remedy, decide by hand'),
              '')) AS detail,
    CAST(s.campaign_id AS STRING) AS campaign_id, CAST(s.keyword_id AS STRING) AS keyword_id
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD` s
  LEFT JOIN (SELECT CAST(keyword_id AS STRING) kid, bid
             FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current) live_kw
    ON live_kw.kid = CAST(s.keyword_id AS STRING)
  LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, daily_budget
             FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`) live_c
    ON s.keyword_id IS NULL AND live_c.cid = CAST(s.campaign_id AS STRING)
  LEFT JOIN (SELECT DISTINCT campaign_id, COALESCE(keyword_id, '') kid, engine, action,
                    suggested_bid, suggested_budget
             FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
             WHERE snapshot_date = (SELECT MAX(snapshot_date)
                                    FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)) pr
    ON pr.campaign_id = CAST(s.campaign_id AS STRING)
   AND pr.kid = COALESCE(CAST(s.keyword_id AS STRING), '')
  WHERE s.verdict = 'REVERSED'
    AND s.remedy_value IS NOT NULL
    AND s.next_change_date IS NULL
    AND ABS(COALESCE(live_kw.bid, live_c.daily_budget) - SAFE_CAST(s.new_value AS FLOAT64)) <= 0.011
    AND ABS(SAFE_CAST(s.remedy_value AS FLOAT64) - SAFE_CAST(s.new_value AS FLOAT64)) > 0.011  -- no-op remedies out
    AND s.read_gate_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
)

SELECT * FROM planned
UNION ALL SELECT * FROM happened
UNION ALL SELECT * FROM verdict_new
UNION ALL SELECT * FROM action_items;
