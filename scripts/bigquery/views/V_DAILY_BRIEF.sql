-- =============================================
-- V_DAILY_BRIEF — one query answers Ori's three daily questions (2026-08-15).
-- Spec: architecture/DAILY_BRIEF.md.
--
-- (Ori 2026-08-15): "i can ask you daily what was planned, what actually happened and what are
-- your action items. the purpose is to make it better. meaning if after a change it became worse
-- this is not good."
--
-- FIVE SECTIONS, one uniform row shape, so the whole brief is SELECT * ORDER BY section:
--   PLANNED      — the latest FACT_ENGINE_PROPOSALS snapshot, GATE-FILTERED: what the engine wants
--                  done today, one price per keyword.
--   SKIPPED      — the instructions the gate refused, with the gate's own sentence and the value
--                  they wanted. Recorded, never deleted; just not on the list you upload from.
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
--
-- ############################################################################
-- # v27.102 — ONE KEYWORD, ONE PRICE. THE BRIEF READS THE GATE'S VERDICT NOW. #
-- ############################################################################
-- (2026-08-21, found while preparing a hand-built upload.) This view read the very table
-- SP_ENGINE_PREFLIGHT stamps its verdict onto — and never read the verdict column. So every
-- collision loser the gate had already refused was printed in PLANNED beside the instruction that
-- beat it, at ITS OWN price, with nothing on the row to say it had lost. On a keyword three
-- engines instructed, the morning list offered three different bids for the same target and no
-- way to tell which one the account should get. The bulksheet is built BY HAND from this list, so
-- the bid that reached Amazon was decided by which line the eye landed on first.
--
-- The gate itself was never broken: it resolves every contention to a single surviving
-- instruction, and the surviving set on the day this was found carried exactly one price per
-- (campaign, key, lever). It resolved them onto the table and no reader downstream ever asked.
--
-- THREE PLACES QUOTED A PRICE; ALL THREE NOW QUOTE THE SURVIVOR:
--   1. PLANNED lists exportable instructions only (verdict GO or REVIEW, or none at all — an
--      unjudged row fails OPEN and is still a plan). REVIEW rows keep their place on the list and
--      say in the first clause that they need eyes before they are sent.
--   2. HAPPENED's "the engine proposed N" quote. It joined on (day, campaign, keyword) with no
--      verdict test, so a hand change on a contended keyword printed once PER PROPOSING ENGINE,
--      each line quoting a different number. It now reads the `survivor` CTE — one instruction
--      per key per day — so an applied change is one row quoting one price.
--   3. ACTION_ITEM's CONFLICT clause, which demotes a scorecard restore to REVIEW because "a live
--      engine outranks the remedy". A refused instruction is not a live engine, and it was both
--      demoting restores it had no standing to demote and duplicating the action item once per
--      proposing engine. Same CTE, same rule.
--
-- NOTHING IS DELETED. The refused instructions move to their own SKIPPED section carrying the
-- gate's plain sentence and the value they wanted, so the morning read still shows every opinion
-- the engine had — it just stops offering them as prices to copy. This is the same doctrine
-- SP_ENGINE_PREFLIGHT states for the holdout arm: block the export, never the judgement.
--
-- FAIL OPEN. Every test is COALESCE(verdict, 'GO') != 'EXCLUDE'. A partition written before
-- verdicts existed, or one the gate has not stamped yet, reads as a plan — the brief must not go
-- blank because a procedure did not run.
--
-- SECTION_RANK RENUMBERED, order unchanged: PLANNED 1, SKIPPED 2, HAPPENED 3, VERDICT_NEW 4,
-- ACTION_ITEM 5. The ritual is ORDER BY section_rank, so the sections still arrive in the order
-- they always did with the new one in the place it belongs.
--
-- The standing assertion for this defect is V_ENGINE_HEALTH's plan_price_ambiguity check, with a
-- pre-deploy twin in scripts/bigquery/check_one_price_per_key.py.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_DAILY_BRIEF` AS
WITH latest AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
),

-- v27.102: today's judged instructions, read ONCE and split two ways below. `exportable` is the
-- whole rule of this view in one expression — an instruction is a plan unless the gate refused
-- it, and an unstamped instruction is a plan (COALESCE, so a missing verdict fails open).
today AS (
  SELECT p.*, (COALESCE(p.verdict, 'GO') != 'EXCLUDE') AS exportable
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` p, latest
  WHERE p.snapshot_date = latest.d
    -- v27.98: PLANNED is "what the engine wants DONE today". A row the last-day veto held is the
    -- engine saying wait, and it is now RECORDED in the proposal table (verdict EXCLUDE, with the
    -- veto's own sentence) rather than erased — but it belongs in the audit trail, not on the
    -- morning list, exactly as the table's own header argues about hold rows. This keeps the
    -- brief byte-identical to what it printed before held rows existed.
    AND p.hold_source IS NULL
),

-- v27.102: THE SURVIVING INSTRUCTION, one per (day, campaign, keyword). Used wherever the brief
-- QUOTES a price back at the reader — the HAPPENED comparison and the ACTION_ITEM conflict flag.
-- Both used to join the raw proposal table, so a contended keyword duplicated the row once per
-- proposing engine and each copy quoted a different number.
-- The pick order is deliberate and total: instructions that CARRY a value first (a negate has no
-- value, and "the engine proposed" followed by nothing is not a sentence), then the ownership
-- ladder SP_ENGINE_PREFLIGHT ranks by, then the engine name so a re-run is byte-identical.
survivor AS (
  SELECT snapshot_date, campaign_id, COALESCE(keyword_id, '') AS kid,
         CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
         engine, action, suggested_bid, suggested_budget
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE hold_source IS NULL
    AND COALESCE(verdict, 'GO') != 'EXCLUDE'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY snapshot_date, campaign_id, COALESCE(keyword_id, '')
    ORDER BY IF(COALESCE(suggested_bid, suggested_budget) IS NULL, 1, 0),
             CASE engine WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                         WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END,
             engine) = 1
),
-- today's slice of the same CTE. A separate name because BigQuery refuses a scalar subquery
-- inside a JOIN predicate ("Unsupported subquery with table in join predicate") — the date
-- restriction has to happen before the join, not inside it.
survivor_today AS (
  SELECT s.* FROM survivor s, latest WHERE s.snapshot_date = latest.d
),

planned AS (
  SELECT
    'PLANNED' AS section, 1 AS section_rank,
    p.engine AS source, p.campaign_name, p.target_text AS item, p.action,
    COALESCE(p.current_bid, p.current_budget) AS from_value,
    COALESCE(p.suggested_bid, p.suggested_budget) AS to_value,
    p.grain AS status,
    -- a REVIEW row is exportable but not unattended: the gate's condition leads the sentence, so
    -- it cannot be copied off this list without the caution being read first
    IF(p.verdict = 'REVIEW',
       CONCAT('check before sending — ', COALESCE(p.verdict_reason, 'flagged by the gate'),
              ' · ', p.reason),
       p.reason) AS detail,
    p.campaign_id, p.keyword_id
  FROM today p
  WHERE p.exportable
),

-- v27.102: refused, recorded, and off the price list. The gate's own sentence first (why it lost),
-- then the value it wanted, so the record of the opinion survives in full.
skipped AS (
  SELECT
    'SKIPPED' AS section, 2 AS section_rank,
    p.engine AS source, p.campaign_name, p.target_text AS item, p.action,
    COALESCE(p.current_bid, p.current_budget) AS from_value,
    COALESCE(p.suggested_bid, p.suggested_budget) AS to_value,
    COALESCE(p.verdict, 'EXCLUDE') AS status,
    CONCAT(COALESCE(p.verdict_reason, 'refused by the gate'),
           ' · what it wanted: ', p.reason) AS detail,
    p.campaign_id, p.keyword_id
  FROM today p
  WHERE NOT p.exportable
),

happened AS (
  -- the change log carries no campaign NAME — join the dim (cheap, current row only)
  SELECT
    'HAPPENED' AS section, 3 AS section_rank,
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
  -- v27.102: the SURVIVING instruction, not every instruction. This join used to reach the raw
  -- proposal table, so one applied change on a contended keyword became one brief row per
  -- proposing engine — each quoting a different proposed price at a reader holding one bulksheet.
  -- The v27.98 hold_source rule and the gate's verdict both live in the CTE now.
  LEFT JOIN survivor p
    ON p.snapshot_date = DATE(a.applied_at, 'America/Los_Angeles')
   AND p.campaign_id = CAST(a.campaign_id AS STRING)
   AND p.kid = COALESCE(CAST(a.keyword_id AS STRING), '')
   -- v27.102: AND ON THE SAME LEVER, derived from the change's own values. Campaign-grain changes
   -- key on kid = '' and so does every NEGATE proposal in the campaign (a negate has no keyword
   -- id), so a search-term block was marking hand PAUSES as "planned" and then printing a blank
   -- sentence, because the CONCAT quoting the proposed price returns NULL on a value-less row.
   -- A change carrying no value at all — a pause — matches nothing, which is the honest answer:
   -- PAUSE is not one of the levers the engine proposes on.
   AND p.lever = CASE WHEN a.new_budget IS NOT NULL OR a.old_budget IS NOT NULL THEN 'BUDGET'
                      WHEN a.new_bid IS NOT NULL OR a.old_bid IS NOT NULL THEN 'BID'
                      ELSE 'NONE' END
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = CAST(a.campaign_id AS STRING)
  WHERE a.applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
),

verdict_new AS (
  SELECT
    'VERDICT_NEW' AS section, 4 AS section_rank,
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
  --   3. CONFLICT FLAG — if TODAY's proposal snapshot has an engine instructing this key AND the
  --      gate let that instruction stand, the row demotes to REVIEW naming the conflict
  --      (single-home: a live engine outranks a scorecard remedy; low stock outranks everything).
  --      v27.102: "and the gate let it stand" is new — a refused instruction is not a live engine.
  SELECT
    'ACTION_ITEM' AS section, 5 AS section_rank,
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
  -- v27.102: only a SURVIVING instruction is "a live engine". A refused one has no standing to
  -- demote a restore to REVIEW, and this join used to duplicate the action item once per
  -- proposing engine, each copy naming a different conflicting price.
  LEFT JOIN survivor_today pr
    ON pr.campaign_id = CAST(s.campaign_id AS STRING)
   AND pr.kid = COALESCE(CAST(s.keyword_id AS STRING), '')
   -- v27.102: AND ON THE SAME LEVER. A budget restore keys on kid = '' — and so does every
   -- NEGATE proposal in the campaign, because a negate has no keyword id. So a search-term block
   -- was demoting campaign-budget restores to REVIEW as though it were a competing budget
   -- instruction, and printing a blank explanation while it did it (a negate carries no value, so
   -- the CONCAT that quotes the conflicting price returned NULL and took the whole sentence with
   -- it). One BOTTLE budget restore was sitting on the morning action list in exactly that state.
   AND pr.lever = s.value_kind
  WHERE s.verdict = 'REVERSED'
    AND s.remedy_value IS NOT NULL
    AND s.next_change_date IS NULL
    AND ABS(COALESCE(live_kw.bid, live_c.daily_budget) - SAFE_CAST(s.new_value AS FLOAT64)) <= 0.011
    AND ABS(SAFE_CAST(s.remedy_value AS FLOAT64) - SAFE_CAST(s.new_value AS FLOAT64)) > 0.011  -- no-op remedies out
    AND s.read_gate_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
)

SELECT * FROM planned
UNION ALL SELECT * FROM skipped
UNION ALL SELECT * FROM happened
UNION ALL SELECT * FROM verdict_new
UNION ALL SELECT * FROM action_items;
