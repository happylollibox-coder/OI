-- =============================================
-- FACT_ENGINE_PROPOSALS — the engine's memory of its own opinions (2026-08-15).
-- Spec: architecture/DAILY_BRIEF.md.
--
-- WHY THIS EXISTS (Ori 2026-08-15): "i want you to be able to check the data easily so i can ask
-- you daily what was planned, what actually happened and what are your action items. the purpose
-- is to make it better. meaning if after a change it became worse this is not good."
-- FACT_PPC_CHANGE_LOG remembers what was APPLIED. Nothing remembered what was PROPOSED — so
-- "did the engine call it right?" was only answerable for suggestions Ori happened to upload,
-- and "the engine said X, Ori did Y" (the manual-divergence question, the doctrine that manual
-- changes mean the MODEL needs fixing) was not answerable at all. This table is that memory:
-- one row per (day, engine, instruction), applied or not.
--
-- Written once per day by SP_SNAPSHOT_ENGINE_PROPOSALS inside SP_ORCHESTRATE_DAILY_REFRESH
-- (delete-today-then-insert, so a same-day re-run replaces rather than duplicates).
-- Read by V_DAILY_BRIEF (PLANNED section + the planned/unplanned split of HAPPENED) and, later,
-- V_MANUAL_DIVERGENCE (engine-finalization plan Task 3.1).
--
-- GRAIN: BID (keyword-level bid move) | BUDGET (campaign-level) | REVIVE (reverdict revival).
-- Only real instructions are stored — HOLD / WATCH / DEFER_* rows are noise and stay out.
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_ENGINE_PROPOSALS` (
  snapshot_date    DATE    NOT NULL,  -- America/Los_Angeles, the OI ads day
  engine           STRING  NOT NULL,  -- LIFT | OOB | LOW_STOCK | LAUNCH | REVERDICT | COACH (v27.72)
  grain            STRING  NOT NULL,  -- BID | BUDGET | REVIVE | NEGATE (v27.72 — target_text holds the term, no values)
  campaign_id      STRING,
  campaign_name    STRING,
  keyword_id       STRING,            -- NULL on BUDGET rows
  target_text      STRING,
  match_type       STRING,
  channel          STRING,            -- SP | SB
  action           STRING  NOT NULL,  -- the engine's own action string, verbatim
  current_bid      FLOAT64,
  suggested_bid    FLOAT64,
  current_budget   FLOAT64,
  suggested_budget FLOAT64,
  reason           STRING             -- the engine's own reason sentence, verbatim
)
PARTITION BY snapshot_date
OPTIONS (description = 'Daily snapshot of every live engine instruction (proposed, whether or not applied). One row per (day, engine, instruction). Written by SP_SNAPSHOT_ENGINE_PROPOSALS; read by V_DAILY_BRIEF. Spec: architecture/DAILY_BRIEF.md.');
