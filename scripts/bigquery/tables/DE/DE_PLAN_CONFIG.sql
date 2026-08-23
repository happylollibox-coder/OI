-- =============================================================================================
-- DE_PLAN_CONFIG — v27.130 (2026-08-23): the declared settings of the next-week money plan,
-- ONE ROW PER CALENDAR STATE. The plan reads this table, never a literal (spec P-13).
--
--   calendar_state   OFF_PEAK | BOOST | PEAK  (FN_PLAN_CALENDAR_STATE decides which one is on)
--   window_days      complete days in the judged window (P-10): 7 off-peak, 3 in BOOST and PEAK
--   allowance_share  share of the GOOD side's window spend handed to the not-good side (P-2):
--                    0.20 off-peak and in PEAK; 0.50 in BOOST (Ori 2026-08-23) — a learning
--                    question; V_PLAN_SCORECARD and the backtest publish the evidence per state
--   live_plan        'B' (rule B judges the window) or 'A' (the ladder judges the side, P-9)
--   ramp_steps       windows over which the allowance closes the gap to today's not-good spend.
--                    P-8 says ONE THIRD of the gap per window, so this is 3 — "ramp thirds" and
--                    ramp_steps are the same setting under two names; the column is named for
--                    the mechanism (steps) because a future ruling may change the count, and
--                    every downstream reader (V_PLAN_WINDOW_JUDGMENT, SP_BUILD_NEXT_WEEK_PLAN,
--                    FACT_PLAN_NEXT_WEEK.ramp_steps, the plan book) already calls it that.
--   min_orders       the order floor rule B applies inside the window (P-3): 2. Read as OBSERVED
--                    orders and never inflated by the settle correction (P-14a) — a count cannot
--                    be fractionally corrected. Lives here so the floor is a setting Ori can
--                    change, not a literal buried in a view.
--   is_active        FALSE = superseded; kept for the audit trail. Readers take the latest
--                    active row per state (QUALIFY ROW_NUMBER ORDER BY updated_at DESC).
--   description      the row in words, for a person reading the table.
--
-- CREATE IF NOT EXISTS + a seed scoped by updated_by = 'plan_seed': re-running the file never
-- destroys a row Ori entered by hand (house DE_ pattern, DE_BUDGET_CONFIG). The ALTER lines make
-- the file converge against a table that already exists, because CREATE TABLE IF NOT EXISTS is a
-- silent no-op there (the defect DE_LAUNCH_INVESTMENT already paid for).
-- Ori changes a setting by INSERTing a new active row for the state with a later updated_at and
-- setting is_active = FALSE on the old one — never by editing this file.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PLAN_CONFIG`
(
  calendar_state   STRING  NOT NULL,
  window_days      INT64   NOT NULL,
  allowance_share  FLOAT64 NOT NULL,
  live_plan        STRING  NOT NULL,
  ramp_steps       INT64   NOT NULL,
  min_orders       INT64   NOT NULL,
  is_active        BOOL    NOT NULL,
  description      STRING,
  updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_by       STRING
)
OPTIONS (description = "v27.130 (2026-08-23) next-week money plan settings, one row per calendar state (OFF_PEAK | BOOST | PEAK): window_days (complete days, P-10), allowance_share (share of the good side's window spend for the not-good side, P-2/P-13), live_plan (A|B, P-9), ramp_steps (P-8, one third of the gap per window = 3), min_orders (the window order floor, P-3, read on observed orders and never inflated by the settle correction). The plan reads the latest is_active row per state; never a literal. Seed rows carry updated_by = 'plan_seed' and are the only rows the DDL file rewrites; Ori changes a setting by inserting a new active row and retiring the old. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13. SOP: architecture/NEXT_WEEK_MONEY.md");

ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS min_orders  INT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS description STRING;

DELETE FROM `onyga-482313.OI.DE_PLAN_CONFIG` WHERE updated_by = 'plan_seed';

INSERT INTO `onyga-482313.OI.DE_PLAN_CONFIG`
  (calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
   is_active, description, updated_at, updated_by)
VALUES
  ('OFF_PEAK', 7, 0.20, 'B', 3, 2, TRUE,
   'P-13 OFF-PEAK: judge each keyword on the 7 complete days ending at the ads watermark minus one; hand the not-good side one fifth of what the good side spent in that window, closing one third of the gap to the not-good spend of today each window. A keyword needs 2 orders in the window to be judged good (Ori 2026-08-23).',
   CURRENT_TIMESTAMP(), 'plan_seed'),
  ('BOOST',    3, 0.50, 'B', 3, 2, TRUE,
   'P-13 BOOST (the run-up between boost_start and peak_start on the house calendar): judge on 3 complete days and hand the not-good side HALF of the window spend of the good side, so seasonal terms with no record yet can buy a seat before the peak starts. Ori is not sure 0.50 is right — the scorecard and the backtest answer it per state (Ori 2026-08-23, a learning question).',
   CURRENT_TIMESTAMP(), 'plan_seed'),
  ('PEAK',     3, 0.20, 'B', 3, 2, TRUE,
   'P-13 PEAK (peak_start through the cooldown of the season, or the anchor date plus three days where no cooldown is set): judge on 3 complete days and hold the not-good side to one fifth of the window spend of the good side until Ori says otherwise — by the time a peak starts the money should already be seated.',
   CURRENT_TIMESTAMP(), 'plan_seed');
