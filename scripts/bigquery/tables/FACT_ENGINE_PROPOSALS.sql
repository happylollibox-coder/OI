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
--
-- ── v27.98 (Ori 2026-08-21): THE ONE EXCEPTION, AND WHY IT IS AN EXCEPTION ───────────────────
-- The last-day veto (v27.75/v27.76) does not decline to propose — it takes a proposal the engine
-- ALREADY MADE and holds it for a day. It does that by rewriting action to 'HOLD' and NULLing
-- suggested_bid, which breaks BOTH conjuncts of the filter above, so the row and its reason
-- vanished from this table entirely. That made the veto the ONLY suppression in the engine that
-- ERASES rather than LABELS: every other one — ownership deferral, single-home dedup, no-ops,
-- holds, the holdout arm — is recorded here in full with verdict = 'EXCLUDE' and a plain-language
-- verdict_reason. SP_ENGINE_PREFLIGHT states the doctrine for the holdout arm in its own header:
-- "the proposal is still recorded ... only the verdict says EXCLUDE. Block the export, never the
-- judgement." A vetoed row is now recorded the same way, and it is the ONLY class of row here
-- that carries action = 'HOLD'.
--   held_action  — the action the engine intended before the veto (INCREASE_BID, DARK_BRAKE, ...)
--   held_bid     — the bid it intended. DELIBERATELY NOT suggested_bid: a value in suggested_bid
--                  is an instruction, and a held row must be unable to become one no matter which
--                  consumer reads it. suggested_bid stays NULL and action stays 'HOLD', so every
--                  reader of the existing columns behaves exactly as before.
--   hold_source  — which arm held it: LAST_DAY_VETO_RAISE | LAST_DAY_VETO_CUT. NULL on every
--                  other row, so it is also the flag that tells a veto hold apart from a
--                  collision / claim / holdout exclusion — the is_holdout idea, one column over.
--                  The two arms are NOT equally strong and the split is the whole point: a
--                  filling day already at/above the cut bar can only rise as attribution accrues
--                  (strong), while a 0.00x filling day is ambiguous (weak).
-- CONSUMER CONTRACT: held rows are recorded, never exported. SP_ENGINE_PREFLIGHT skips them
-- outright (they are not instructions to judge, they carry no value, and admitting them would let
-- a held row win a collision and silence the engine that was ready to act), so they never reach
-- T_ENGINE_PREFLIGHT, the EnginePreflight cube, the decisions feed or DoPage's bulksheet.
-- V_DAILY_BRIEF's PLANNED section skips them for the same reason the header gives above.
-- V_HOLDOUT_READOUT deliberately DOES read them, through held_action/held_bid — the engine's
-- intended action class is exactly what that trial splits on.
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
  reason           STRING,            -- the engine's own reason sentence, verbatim
  -- stamped by SP_ENGINE_PREFLIGHT (and, for veto holds, written straight by the snapshot)
  verdict          STRING,            -- GO | EXCLUDE | REVIEW
  verdict_reason   STRING,            -- plain-language, read aloud
  ad_group_id      STRING,            -- Phase 6 Task 1: the upload key (SB negates: a comma-list)
  reason_short     STRING,            -- Phase 6 Task 3: the 5-second why
  season_relax_applied BOOL,          -- v27.72: peak-converting negate / season-relaxed revival
  -- v27.98 the last-day veto's held proposal (see the header). NULL on every other row.
  held_action      STRING,            -- the action the engine intended before the veto
  held_bid         FLOAT64,           -- the bid it intended — never suggested_bid, never exported
  hold_source      STRING             -- LAST_DAY_VETO_RAISE | LAST_DAY_VETO_CUT
)
PARTITION BY snapshot_date
OPTIONS (description = 'Daily snapshot of every live engine instruction (proposed, whether or not applied). One row per (day, engine, instruction). Written by SP_SNAPSHOT_ENGINE_PROPOSALS; read by V_DAILY_BRIEF. Spec: architecture/DAILY_BRIEF.md.');
