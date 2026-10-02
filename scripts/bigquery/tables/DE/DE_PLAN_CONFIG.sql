-- =============================================================================================
-- DE_PLAN_CONFIG — v27.132 (2026-08-23), v27.155 (2026-10-01): the declared settings of the
-- next-week money plan, ONE ACTIVE ROW PER CALENDAR STATE. The plan reads this table, never a
-- literal (spec P-13). v27.155 adds the two P-14c settings and change_reason (see below).
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
--   strong_day_mult  P-14c (Ori 2026-09-17): the P-14b hold is granted only when the LAST complete
--                    day of the window returned, corrected, at least this many times the family
--                    bar. 1.5 in every state.
--   strong_day_min_orders  ...and carried at least this many OBSERVED orders on that day. 1.
--                    Both were literals in V_PLAN_WINDOW_JUDGMENT's k CTE until v27.155; the judge
--                    now reads them from here per calendar state, and the seed below carries the
--                    values the k CTE carried, so moving them changed no verdict.
--   change_reason    why this row was written: the sentence a retire-then-insert carries (Ori's
--                    words, or a proposal id once the learning contract's proposer exists). The
--                    seed rows name the rulings they encode.
--
-- HISTORY (v27.155): every value that was ever in force stays readable, in two places.
--   1. This table. A change is RETIRE-then-INSERT (the SOP's recipe), so a superseded row stays
--      here with is_active = FALSE and its updated_at still dates it (FN_PLAN_SCORECARD reads the
--      order floor in force at built_at exactly that way). NO ROW IS EVER DELETED, except by the
--      seed guard below, and the guard deletes only a row that is provably the untouched seed —
--      which the INSERT then writes back with the same settings and the same sentinel updated_at.
--   2. FACT_THRESHOLD_HISTORY. SP_SNAPSHOT_THRESHOLDS (orchestrator Refresh Task 10.1) appends a
--      row whenever a row of this table differs from its last snapshot — including the two shapes
--      the in-table trail cannot date: an UPDATE in place, and a retirement (is_active flips but
--      updated_at does not move).
--
-- CREATE IF NOT EXISTS, then a seed that DEFERS TO ANY ROW THAT IS NOT STILL THE SEED. The ALTER
-- lines make the file converge against a table that already exists, because CREATE TABLE IF NOT
-- EXISTS is a silent no-op there (the defect DE_LAUNCH_INVESTMENT already paid for).
--
-- WHY THE SEED IS WRITTEN THE WAY IT IS — TWO DEFECTS, BOTH PAID FOR IN MONEY TERMS.
--
-- v27.130 ran an unconditional `DELETE WHERE updated_by = 'plan_seed'` and re-INSERTed the seed
-- rows ACTIVE with a fresh CURRENT_TIMESTAMP(). Ori's row survived the delete — and stopped
-- being the row anyone read, because the reader takes the LATEST active row per state and the
-- re-inserted seed was newer.
--
-- v27.131 fixed that by keying the guard on updated_by: the seed deleted only its own row, and
-- only for a state with no non-seed row. THAT GUARD STILL REVERTED ONE SHAPE OF HAND CHANGE,
-- because a hand change does not have to arrive as a new row. Replayed end to end on a TMP_
-- copy: `UPDATE ... SET allowance_share = 0.33 WHERE calendar_state = 'PEAK' AND is_active`
-- leaves updated_by = 'plan_seed' on the row, so the v27.131 DELETE still fired and the INSERT
-- re-seeded — 0.33 back to 0.20, silently. The same clause also RE-ACTIVATED a state Ori had
-- deliberately retired without replacing (retire the only seed row, insert nothing, re-deploy →
-- it came back ACTIVE). allowance_share multiplies the pot, so both revert real money with no
-- error and no log line.
--
-- v27.132 keys the guard on the VALUES, not on who wrote them, and declares the seed ONCE:
--   1. the seed rows are built into a TEMP table, so the DELETE and the INSERT read the same
--      declaration and two copies of it can never drift apart;
--   2. the DELETE removes a row only when EVERY SETTING on it still equals the declared seed
--      AND the row is still active — i.e. only a row that is provably untouched. Change any
--      setting by any means (a new row, or an UPDATE in place), or retire the row, and the
--      DELETE stops seeing it. What still converges on this file is the DESCRIPTION of an
--      otherwise-untouched seed row, which is the only reason the DELETE exists at all;
--   3. the INSERT writes only a state that has NO row at all, so a retired state stays retired;
--   4. seed rows carry a DECLARED SENTINEL updated_at (the date of the ruling, a declared
--      constant), never a deploy clock — so even a stray seed row can never out-rank by recency
--      a row Ori entered by hand.
--
-- v27.155 — THE TWO P-14c SETTINGS JOIN THE SEED, AND THE PRE-COLUMN SEED ROWS ARE CONVERTED.
-- ALTER adds strong_day_mult, strong_day_min_orders and change_reason as NULL on every row that
-- already exists (BigQuery cannot add a REQUIRED column). On such a row NULL means "the column did
-- not exist yet", not a setting someone chose, so the guard reads a NULL in either of the two new
-- settings as untouched: a seed row whose six older settings still equal the declaration and whose
-- new settings are NULL is deleted, and the INSERT writes it back with 1.5 / 1, the declared
-- change_reason and the same sentinel updated_at — the conversion, done by the seed's own recipe.
-- A row on which anyone has set a value in those columns, any value, is never matched.
-- One consequence, stated: setting one of the two new columns back to NULL by an UPDATE in place on
-- an otherwise untouched seed row makes that row look untouched again, and the next deploy writes
-- 1.5 / 1 there. NULL is not a setting — acceptance C02 fails on it, and for today's calendar
-- state V_PLAN_WINDOW_JUDGMENT raises an error rather than judge with no rule — so that is the one
-- in-place edit a deploy still reverts.
-- A row someone else wrote (updated_by is not 'plan_seed') is never touched, even with NULL in the
-- new columns: it keeps reading NULL until its owner retires it and inserts a row carrying the two
-- settings, and C02 fails until then. On 2026-10-01 the live table held only the three seed rows.
-- REPLAYED 2026-10-01 (LA) on TMP_ copies of the live table, this file with the table name
-- swapped, every scenario as stated: the conversion (three seed rows, NULL in the new columns ->
-- 1.5 / 1, same sentinel, change_reason written); a second run (every column identical); an UPDATE
-- in place of strong_day_mult to 1.3 on PEAK (kept); of allowance_share to 0.33 (kept); PEAK
-- retired with no replacement (stays retired, no row added); retire-then-insert of a hand PEAK row
-- at 1.3 (kept, the retired seed row untouched); a hand PEAK row written before the columns
-- existed (kept with NULL, the retired seed row untouched); strong_day_mult set back to NULL in
-- place on a seed row (re-seeded to 1.5, the consequence above); and a fresh CREATE (three seed
-- rows at 1.5 / 1).
-- The DELETE and the INSERT run in ONE TRANSACTION, so a failure between them cannot leave a
-- state with no row (the judge would then have no window for that state). Replayed 2026-10-01 on
-- a TMP_ copy with an ERROR() injected between the two: the script failed and all three seed rows
-- were still there.
--
-- THE GUARANTEE, STATED EXACTLY: re-running this file can never change a SETTING that holds a
-- value, in any state, however it was changed — a new active row, or an UPDATE in place — and can
-- never re-activate a state that was retired. It can only refresh the description and the
-- change_reason of a seed row whose settings are still, to the value, the ones declared below, and
-- fill the two P-14c settings on a seed row where they are still NULL.
-- PLAN_CONFIG_acceptance C06/C07 are the alarms for the v27.130 shape; C09 is the alarm for the
-- v27.131 shape — it goes red the moment a plan_seed row's settings stop matching this file, so
-- an in-place edit is visible instead of silent (and the answer is to retire-and-insert, which
-- is the recipe the SOP publishes).
--
-- Ori changes a setting by RETIRING whatever is active for the state and then INSERTing his own
-- active row — in that order, so the recipe is idempotent (see the SOP). Never by editing this
-- file. An UPDATE in place now survives a re-deploy too, but it leaves the row labelled
-- 'plan_seed' and trips C09; the retire-and-insert recipe is still the one to use.
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
  updated_by       STRING,
  -- v27.155. NULLABLE because an existing table can only gain NULLABLE columns; the judge refuses
  -- a NULL and acceptance C02 fails on one, so in practice both settings are required.
  strong_day_mult        FLOAT64,
  strong_day_min_orders  INT64,
  change_reason          STRING
)
;

-- SET OPTIONS, not CREATE ... OPTIONS: CREATE TABLE IF NOT EXISTS is a silent no-op against a
-- table that already exists, so the description would never converge.
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` SET OPTIONS(description = "v27.155 (2026-10-01): adds strong_day_mult (FLOAT64) and strong_day_min_orders (INT64), the P-14c last-day test (Ori 2026-09-17: the P-14b hold is granted only when the last complete day of the window carried at least strong_day_min_orders observed orders and a corrected return of at least strong_day_mult x the family bar), moved here from the V_PLAN_WINDOW_JUDGMENT k CTE with the values it carried (1.5 / 1 in every state), and change_reason (STRING, why a retire-then-insert row was written). History: a change is retire-then-insert, so superseded rows stay with is_active = FALSE; no row is ever deleted except an untouched seed row, which the seed writes back with the same settings and sentinel; FACT_THRESHOLD_HISTORY (SP_SNAPSHOT_THRESHOLDS, orchestrator Refresh Task 10.1) also records every row each time it differs from its last snapshot, including an UPDATE in place and a retirement. A seed row whose two new settings are NULL predates the columns and is converted by the seed guard; the judge raises an error on a NULL rather than judge with no rule. v27.132 (2026-08-23) next-week money plan settings, one row per calendar state (OFF_PEAK | BOOST | PEAK): window_days (complete days, P-10), allowance_share (share of the good side's window spend for the not-good side, P-2/P-13), live_plan (A|B, P-9), ramp_steps (P-8, one third of the gap per window = 3), min_orders (the window order floor, P-3, read on observed orders and never inflated by the settle correction). The plan reads the latest is_active row per state; never a literal. Seed rows carry updated_by = 'plan_seed' and a declared sentinel updated_at. THE DEPLOY GUARANTEE, EXACTLY: re-running the DDL can never change the SETTINGS of any state, however they were changed (a new active row, or an UPDATE in place), and can never re-activate a retired state; it can only refresh the description (from v27.155 also change_reason, and the two P-14c settings while they are still NULL) of a seed row whose settings still equal the declared seed to the value. That is enforced by comparing VALUES, not updated_by — the v27.131 guard keyed on updated_by and still reverted an in-place UPDATE of a seeded row, and still re-activated a deliberately retired one. Acceptance C09 goes red when a plan_seed row's settings stop matching the DDL, so an in-place edit is visible; the supported recipe is still retire-then-insert. window_days has an older house authority in V_PEAK_WINDOW_RULE + DE_PEAK_WINDOW_OVERRIDE; P-11 makes this table the plan's authority and acceptance C08 goes red if the two disagree. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13. SOP: architecture/NEXT_WEEK_MONEY.md");

-- v27.155: one ALTER per statement. The two ALTERs that converged the v27.130 table (min_orders,
-- description) are gone: the live table has carried both columns since 2026-08-23 and the CREATE
-- above declares them. BigQuery allows five metadata updates per table in ten seconds, and SET
-- OPTIONS plus five ALTERs failed on the sixth ("too many table update operations for this
-- table"), replayed on a TMP_ copy on 2026-10-01 — an ALTER on a column that already exists still
-- counts. SET OPTIONS plus these three is four.
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS strong_day_mult       FLOAT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS strong_day_min_orders INT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS change_reason         STRING;

-- THE SEED, DECLARED ONCE. Both the DELETE and the INSERT read this table, so the values the
-- guard compares against and the values the seed writes cannot drift apart. v27.155 adds the two
-- P-14c settings (the values V_PLAN_WINDOW_JUDGMENT's k CTE carried from v27.147 to v27.154) and
-- the change_reason every seed row carries.
CREATE TEMP TABLE _plan_config_seed AS
SELECT * FROM UNNEST([
  STRUCT('OFF_PEAK' AS calendar_state, 7 AS window_days, 0.20 AS allowance_share,
         'B' AS live_plan, 3 AS ramp_steps, 2 AS min_orders,
         1.5 AS strong_day_mult, 1 AS strong_day_min_orders,
         'P-13 OFF-PEAK: judge each keyword on the 7 complete days ending at the fenced window end (the ads watermark minus one, and never a day younger than two — P-14a); hand the not-good side one fifth of what the good side spent in that window, closing one third of the gap to the not-good spend of today each window. A keyword needs 2 orders in the window to be judged good (Ori 2026-08-23). A keyword that was good is held on the good side while its window settles only if the last day of the window carried at least 1 order and returned at least 1.5 times the family bar (P-14c, Ori 2026-09-17).' AS description),
  STRUCT('BOOST', 3, 0.50, 'B', 3, 2, 1.5, 1,
         'P-13 BOOST (the run-up between boost_start and peak_start on the house calendar): judge on 3 complete days and hand the not-good side HALF of the window spend of the good side, so seasonal terms with no record yet can buy a seat before the peak starts. Ori is not sure 0.50 is right — the scorecard and the backtest answer it per state (Ori 2026-08-23, a learning question). A keyword that was good is held on the good side while its window settles only if the last day of the window carried at least 1 order and returned at least 1.5 times the family bar (P-14c, Ori 2026-09-17).'),
  STRUCT('PEAK', 3, 0.20, 'B', 3, 2, 1.5, 1,
         'P-13 PEAK (peak_start through the cooldown of the season, or the anchor date plus three days where no cooldown is set): judge on 3 complete days and hold the not-good side to one fifth of the window spend of the good side until Ori says otherwise — by the time a peak starts the money should already be seated. A keyword that was good is held on the good side while its window settles only if the last day of the window carried at least 1 order and returned at least 1.5 times the family bar (P-14c, Ori 2026-09-17).')
]);

BEGIN TRANSACTION;

-- Removes ONLY a row that is provably still the untouched seed: same state, every setting equal
-- to the declaration above, still active, and no non-seed row for that state. Anything Ori has
-- touched — a new row, an UPDATE in place, or a retirement — stops matching and survives.
-- The two P-14c settings match when equal OR still NULL (the row predates the columns; see the
-- header): that is how the seed rows written before v27.155 are converted.
DELETE FROM `onyga-482313.OI.DE_PLAN_CONFIG` t
WHERE t.updated_by = 'plan_seed'
  AND t.is_active
  AND EXISTS (SELECT 1 FROM _plan_config_seed s
              WHERE s.calendar_state  = t.calendar_state
                AND s.window_days     = t.window_days
                AND s.allowance_share = t.allowance_share
                AND s.live_plan       = t.live_plan
                AND s.ramp_steps      = t.ramp_steps
                AND s.min_orders      = t.min_orders
                AND (t.strong_day_mult       IS NULL OR s.strong_day_mult       = t.strong_day_mult)
                AND (t.strong_day_min_orders IS NULL OR s.strong_day_min_orders = t.strong_day_min_orders))
  AND NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_PLAN_CONFIG` o
                  WHERE o.calendar_state = t.calendar_state
                    AND o.updated_by IS DISTINCT FROM 'plan_seed');

-- Seeds only a state that has no row at all, and stamps the declared sentinel updated_at.
INSERT INTO `onyga-482313.OI.DE_PLAN_CONFIG`
  (calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
   strong_day_mult, strong_day_min_orders,
   is_active, description, change_reason, updated_at, updated_by)
SELECT s.calendar_state, s.window_days, s.allowance_share, s.live_plan, s.ramp_steps,
       s.min_orders, s.strong_day_mult, s.strong_day_min_orders, TRUE, s.description,
       'Seed. window_days, allowance_share, live_plan, ramp_steps and min_orders are ruling P-13 (Ori 2026-08-23). strong_day_mult 1.5 and strong_day_min_orders 1 are ruling P-14c (Ori 2026-09-17), moved on 2026-10-01 from the k CTE of V_PLAN_WINDOW_JUDGMENT with the values it carried, so no verdict changed.',
       TIMESTAMP '2026-08-23 00:00:00 UTC',   -- the date of ruling P-13, a declared constant
       'plan_seed'
FROM _plan_config_seed s
WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_PLAN_CONFIG` o
                  WHERE o.calendar_state = s.calendar_state);

COMMIT TRANSACTION;
