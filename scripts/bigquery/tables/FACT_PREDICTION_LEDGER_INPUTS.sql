-- =============================================================================================
-- FACT_PREDICTION_LEDGER_INPUTS — v27.177 (2026-10-04, learning piece 2 fix L1): the keyword-state
-- inputs each plan night's predictions are priced on, frozen once per night.
--
-- WHY IT EXISTS. V_PREDICTION_LEDGER v27.172 priced a zero-click OPEN_PROBE (and the family x
-- channel pool it falls back to) by reading FACT_KEYWORD_STATE_HISTORY at query time: the latest
-- snapshot_date before the Los Angeles date of built_at. That history keeps ONE copy per
-- snapshot_date — SP_APPEND_KEYWORD_STATE_HISTORY appends and then prunes every older copy of a date
-- (keeps MAX(captured_at)) — and the view's ks CTE took the newest copy with no
-- captured_at <= built_at filter. So a re-capture or backfill of an older snapshot_date would have
-- moved a stored night's ACT numbers: before the prune the view read the new copy, after it the
-- night's own copy was gone and the snapshot pick fell back to an earlier date. Nothing had moved
-- (measured 2026-10-04: one copy on each of the 49 snapshot_dates); the risk was a hand backfill.
-- The ledger now reads this table instead of the history, so what priced a night is the copy it
-- was frozen from, whatever the history does later.
--
-- GRAIN. One row per (as_of, built_at, campaign_id, keyword_id): every keyword of the night's plan
-- rows (both plans; family and channel as the plan stored them), with the night's snapshot pick —
-- the latest snapshot_date before DATE(built_at, 'America/Los_Angeles') among copies captured at
-- or before built_at, and of that date the newest copy captured at or before built_at — and the
-- keyword's settled 90-day record in that copy (NULL, in_snapshot FALSE, when the copy has no row
-- for it or the night has no such snapshot: the 2026-08-23 night was written before the history's
-- first copy). Plus the night's builder_version as the plan stored it and rule_builder_tag =
-- COALESCE(builder_version, 'pre-v27.170'), which V_PREDICTION_LEDGER's rule_version and
-- builder_version read from here, not from FACT_PLAN_NEXT_WEEK.
--
-- WRITTEN ONCE PER NIGHT by SP_FREEZE_LEDGER_INPUTS(caller): it inserts every night of
-- FACT_PLAN_NEXT_WEEK that has no row here yet, all of the night's keywords in one INSERT, stamped
-- frozen_at / frozen_by. SP_BUILD_NEXT_WEEK_PLAN v27.177 CALLs it right after it writes the night
-- (T_PLAN_BUILD_JUDGMENT's INSERT), so a night is frozen seconds after its built_at; the nights
-- stored before that were frozen by one hand CALL (frozen_by 'L1 migration 2026-10-04').
-- APPEND-ONLY: never updated, never deleted from. A rewrite of a night before its Los Angeles
-- midnight carries a new built_at and is frozen as a new night; the superseded night's rows stay.
-- If a night were ever frozen twice, V_PREDICTION_LEDGER reads its FIRST freeze (MIN(frozen_at)).
--
-- ACCUMULATES: CREATE TABLE IF NOT EXISTS, never replaced. Partitioned by as_of.
--
-- Written by:  SP_FREEZE_LEDGER_INPUTS (CALLed by SP_BUILD_NEXT_WEEK_PLAN, orchestrator Task 20.8c)
-- Read by:     V_PREDICTION_LEDGER; scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql (L5)
-- Controls:    scripts/bigquery/tests/check_ledger_freeze_controls.py
-- SOP:         architecture/LEARNING.md §1 "Why a ledger row never changes", §3, §10 "Fix L1"
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_PREDICTION_LEDGER_INPUTS` (
  as_of                DATE      NOT NULL,  -- the night (FACT_PLAN_NEXT_WEEK.as_of)
  built_at             TIMESTAMP NOT NULL,  -- the night's built_at
  builder_version      STRING,              -- FACT_PLAN_NEXT_WEEK.builder_version of the night, as stored at the freeze (NULL before v27.170)
  rule_builder_tag     STRING    NOT NULL,  -- COALESCE(builder_version, 'pre-v27.170'): the ledger's rule_version suffix
  family               STRING,              -- as the plan stored it
  channel              STRING,              -- as the plan stored it
  campaign_id          STRING    NOT NULL,
  keyword_id           STRING    NOT NULL,
  in_snapshot          BOOL      NOT NULL,  -- the frozen copy holds a row for this keyword
  snapshot_date        DATE,                -- the night's snapshot pick (NULL: no snapshot final at built_at)
  snapshot_captured_at TIMESTAMP,           -- the copy read: the newest copy of snapshot_date captured at or before built_at
  settled_clk90        INT64,               -- FACT_KEYWORD_STATE_HISTORY.settled_clk90 in that copy
  settled_ord90        INT64,               -- FACT_KEYWORD_STATE_HISTORY.settled_ord90 in that copy
  settled_gp90         FLOAT64,             -- FACT_KEYWORD_STATE_HISTORY.settled_gp90 in that copy
  frozen_at            TIMESTAMP NOT NULL,  -- when SP_FREEZE_LEDGER_INPUTS wrote the night
  frozen_by            STRING    NOT NULL   -- its caller (e.g. 'SP_BUILD_NEXT_WEEK_PLAN v27.177')
)
PARTITION BY as_of
CLUSTER BY campaign_id, keyword_id
OPTIONS (description = "v27.177 (2026-10-04, learning piece 2 fix L1): the keyword-state inputs each plan night's predictions are priced on, frozen once per night so a stored night's ACT never moves when FACT_KEYWORD_STATE_HISTORY is re-captured, backfilled or pruned. One row per (as_of, built_at, campaign_id, keyword_id) of the night's plan keywords: the snapshot pick (the latest snapshot_date before the Los Angeles date of built_at among copies captured at or before built_at, and that date's newest such copy, snapshot_captured_at), the keyword's settled_clk90 / settled_ord90 / settled_gp90 in it (NULL with in_snapshot FALSE when absent), and the night's builder_version with rule_builder_tag = COALESCE(builder_version, 'pre-v27.170'), which the ledger's rule_version reads. Written by SP_FREEZE_LEDGER_INPUTS (every night of FACT_PLAN_NEXT_WEEK not yet here), CALLed by SP_BUILD_NEXT_WEEK_PLAN right after it writes a night; the nights stored before v27.177 were frozen by one hand CALL on 2026-10-04. APPEND-ONLY, never updated or deleted from; V_PREDICTION_LEDGER reads each night's first freeze. Acceptance L5 in scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql. SOP: architecture/LEARNING.md.");
