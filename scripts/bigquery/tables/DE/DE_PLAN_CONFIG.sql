-- =============================================================================================
-- DE_PLAN_CONFIG — v27.131 (2026-08-23): the declared settings of the next-week money plan,
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
--                    active row per state (QUALIFY ROW_NUMBER ORDER BY updated_at DESC), so
--                    updated_at is a PRECEDENCE column, not a log line — which is why the seed
--                    rows below carry a fixed sentinel and not the clock of the last deploy.
--   description      the row in words, for a person reading the table.
--
-- CREATE IF NOT EXISTS, then a seed that DEFERS TO A HAND-ENTERED ROW. The ALTER lines make the
-- file converge against a table that already exists, because CREATE TABLE IF NOT EXISTS is a
-- silent no-op there (the defect DE_LAUNCH_INVESTMENT already paid for).
--
-- WHY THE SEED IS WRITTEN THE WAY IT IS (v27.131, the defect v27.130 shipped with).
-- v27.130 ran an unconditional `DELETE WHERE updated_by = 'plan_seed'` and re-INSERTed the seed
-- rows ACTIVE with a fresh CURRENT_TIMESTAMP(). Ori's row survived the delete — and stopped
-- being the row anyone read, because the reader takes the LATEST active row per state and the
-- re-inserted seed was newer. Replayed end to end on a TMP_ copy: BOOST set to 0.35 by hand,
-- one re-run of this file, and the reader returned 0.50 'plan_seed'. allowance_share multiplies
-- the pot, so that reverted real money with no error and no log line.
--
-- Two changes make it impossible:
--   1. the seed only writes a state that has NO row at all, and only deletes its own row for a
--      state nobody has ruled on — so a state Ori has touched is never rewritten, and a state he
--      has not keeps converging on this file as its descriptions change;
--   2. seed rows carry a DECLARED SENTINEL updated_at (the date of the ruling, a declared
--      constant), never a deploy clock — so even a stray seed row can never out-rank by recency
--      a row Ori entered by hand.
-- PLAN_CONFIG_acceptance C06 and C07 are the alarms; C06 is red against v27.130.
--
-- Ori changes a setting by RETIRING whatever is active for the state and then INSERTing his own
-- active row — in that order, so the recipe is idempotent (see the SOP). Never by editing this
-- file.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13.
-- SOP: architecture/NEXT_WEEK_MONEY.md
--
-- ONE MORE AUTHORITY EXISTS ON window_days AND IT IS OLDER THAN THIS TABLE: V_PEAK_WINDOW_RULE
-- over DE_PEAK_WINDOW_OVERRIDE carries Ori's own rule — "in a peak judge on 3 UNLESS last year's
-- same occurrence proved 7 is better" — with an evidence discipline and a re-measure clock per
-- occurrence type. It resolves 3 everywhere today, which is what this table declares, but a
-- granted 7 at a re-measure would put the two in disagreement on the same doctrine on the same
-- day. P-11 (one engine) makes THIS table the plan's authority; acceptance C08 compares them and
-- goes red rather than letting them drift apart in silence.
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
OPTIONS (description = "v27.131 (2026-08-23) next-week money plan settings, one row per calendar state (OFF_PEAK | BOOST | PEAK): window_days (complete days, P-10), allowance_share (share of the good side's window spend for the not-good side, P-2/P-13), live_plan (A|B, P-9), ramp_steps (P-8, one third of the gap per window = 3), min_orders (the window order floor, P-3, read on observed orders and never inflated by the settle correction). The plan reads the latest is_active row per state; never a literal. Seed rows carry updated_by = 'plan_seed' and a declared sentinel updated_at; the DDL seeds only a state that has no row at all and never rewrites a state someone has ruled on, so a re-deploy cannot revert a setting Ori changed by hand (the v27.130 defect). Ori changes a setting by retiring whatever is active for the state and then inserting his own active row, in that order. window_days has an older house authority in V_PEAK_WINDOW_RULE + DE_PEAK_WINDOW_OVERRIDE; P-11 makes this table the plan's authority and acceptance C08 goes red if the two disagree. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13. SOP: architecture/NEXT_WEEK_MONEY.md");

ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS min_orders  INT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS description STRING;

-- Only ever removes the seed's OWN row, and only for a state nobody has ruled on.
DELETE FROM `onyga-482313.OI.DE_PLAN_CONFIG` t
WHERE t.updated_by = 'plan_seed'
  AND NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_PLAN_CONFIG` o
                  WHERE o.calendar_state = t.calendar_state
                    AND o.updated_by IS DISTINCT FROM 'plan_seed');

-- Seeds only a state that has no row at all, and stamps the declared sentinel updated_at.
INSERT INTO `onyga-482313.OI.DE_PLAN_CONFIG`
  (calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
   is_active, description, updated_at, updated_by)
SELECT s.calendar_state, s.window_days, s.allowance_share, s.live_plan, s.ramp_steps,
       s.min_orders, TRUE, s.description,
       TIMESTAMP '2026-08-23 00:00:00 UTC',   -- the date of ruling P-13, a declared constant
       'plan_seed'
FROM UNNEST([
  STRUCT('OFF_PEAK' AS calendar_state, 7 AS window_days, 0.20 AS allowance_share,
         'B' AS live_plan, 3 AS ramp_steps, 2 AS min_orders,
         'P-13 OFF-PEAK: judge each keyword on the 7 complete days ending at the ads watermark minus one; hand the not-good side one fifth of what the good side spent in that window, closing one third of the gap to the not-good spend of today each window. A keyword needs 2 orders in the window to be judged good (Ori 2026-08-23).' AS description),
  STRUCT('BOOST', 3, 0.50, 'B', 3, 2,
         'P-13 BOOST (the run-up between boost_start and peak_start on the house calendar): judge on 3 complete days and hand the not-good side HALF of the window spend of the good side, so seasonal terms with no record yet can buy a seat before the peak starts. Ori is not sure 0.50 is right — the scorecard and the backtest answer it per state (Ori 2026-08-23, a learning question).'),
  STRUCT('PEAK', 3, 0.20, 'B', 3, 2,
         'P-13 PEAK (peak_start through the cooldown of the season, or the anchor date plus three days where no cooldown is set): judge on 3 complete days and hold the not-good side to one fifth of the window spend of the good side until Ori says otherwise — by the time a peak starts the money should already be seated.')
]) s
WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_PLAN_CONFIG` o
                  WHERE o.calendar_state = s.calendar_state);
