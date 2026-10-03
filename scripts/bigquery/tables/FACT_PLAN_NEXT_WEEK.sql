-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK — v27.134 (2026-08-23): the nightly plan for the working families, ONE ROW
-- PER (as_of, plan, campaign_id, keyword_id). Two plans are written every night (spec P-9):
--   plan 'B'  the LIVE plan — the window decides the side and the amount (rule B).
--   plan 'A'  the SHADOW plan — the ladder decides the side, the window decides the amount.
-- Nothing is ever deleted except today's own partition, which the builder rewrites when it re-runs
-- (idempotent on one pass). History is the scorecard's evidence and the P-14b guard's memory of
-- what the plan said last night.
--
-- Written by SP_BUILD_NEXT_WEEK_PLAN (orchestrator Task 20.8c, Task 2 of the plan). Read by
-- V_PLAN_WINDOW_JUDGMENT (last night's side, for P-14b), SP_SNAPSHOT_ENGINE_PROPOSALS (the PLAN
-- engine's rows), V_PLAN_SCORECARD (T+14 grading), tools/build_plan_bulksheet.py and the surfaces.
--
-- The table is created EMPTY here, by Task 1, because the judgement view reads it for the P-14b
-- guard and must not wait for the builder: on the first nights the prior-side read is empty by
-- design and the guard falls back to the declared bootstrap (the ladder's settled record).
-- CREATE TABLE IF NOT EXISTS — re-running this file can never drop a written plan.
--
-- WHAT THE JUDGEMENT VIEW READS BACK FROM HERE, and why Task 2 must write it faithfully. This is
-- not only the scorecard's evidence — it is the plan's MEMORY, and two rulings now depend on it:
--   `side`    the P-14b guard's "was good". Once a keyword has a row here, LAST NIGHT'S SIDE is
--             the authority and the ladder's 90-day record is no longer consulted (v27.134). Write
--             a wrong side and the guard holds the wrong keyword tomorrow.
--   `verdict` the P-5 grace limit. A row whose verdict is 'GRACE' means the one quiet window P-5
--             buys has been SPENT, and the judgement refuses another until the keyword earns a
--             GOOD window back (v27.135: the limit reads this table's WHOLE history, not just last
--             night — the most recent GRACE later than the most recent GOOD is what "spent" means.
--             Reading one night bought one NIGHT of grace on a plan that runs nightly, and made an
--             unserved winner oscillate GOOD / NOT_GOOD / GOOD). A builder that collapses GRACE
--             into 'GOOD' turns grace back into a permanent exemption.
-- UNTIL SP_BUILD_NEXT_WEEK_PLAN WRITES ITS FIRST ROW, both memories are absent by construction:
-- the guard falls back to the ladder bootstrap and the grace limit is NOT ARMED — every judgement
-- row publishes grace_limit_armed = FALSE and says in words that grace is re-granted every night.
-- Arming it is Task 2's job, and it is a doctrine deliverable, not a reporting one.
--
-- v27.134 and v27.135 add the columns the repaired judgement publishes (ALTER TABLE ADD COLUMN on
-- the empty table, mirrored here so the file and the live schema cannot drift): served,
-- prior_grace, last_grace_on, grace_limit_armed, held_despite_evidence, held_with_no_sale,
-- good_side_no_sale, rank_score / rank_dollars_at_stake / rank_closeness / rank_is_degenerate,
-- bid_park / bid_park_source / bid_park_seat_econ and holdout_member. planned_bid and
-- seat_cost_per_day are NULL on every good-side row (P-4).
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §4, §5, P-9, P-14.
-- SOP: architecture/NEXT_WEEK_MONEY.md §2.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
(
  as_of                      DATE    NOT NULL,
  plan                       STRING  NOT NULL,
  is_live_plan               BOOL    NOT NULL,
  family                     STRING,
  book                       STRING,
  campaign_id                STRING,
  campaign_name              STRING,
  keyword_id                 STRING,
  ad_group_id                STRING,
  target_text                STRING,
  match_type                 STRING,
  channel                    STRING,
  is_auto                    BOOL,
  is_pt                      BOOL,
  calendar_state             STRING,
  window_days                INT64,
  window_from                DATE,
  window_to                  DATE,
  watermark                  DATE,
  w_clk                      INT64,
  w_ord                      INT64,
  w_sp                       FLOAT64,
  w_gp                       FLOAT64,
  w_gp_corrected             FLOAT64,
  settle_factor_min          FLOAT64,
  settle_factor_eff          FLOAT64,
  settle_curve_available     BOOL,
  settled                    BOOL,
  settle_due_on              DATE,
  settle_arm                 STRING,
  decided_by                 STRING,
  was_good                   BOOL,
  family_bar                 FLOAT64,
  ret_raw                    FLOAT64,
  ret_corrected              FLOAT64,
  ladder_state               STRING,
  side                       STRING,
  verdict                    STRING,
  is_candidate               BOOL,
  rank_score                 FLOAT64,
  rank_dollars_at_stake      FLOAT64,
  rank_closeness             FLOAT64,
  rank_is_degenerate         BOOL,
  served                     BOOL,
  prior_grace                BOOL,
  last_grace_on              DATE,
  grace_limit_armed          BOOL,
  held_despite_evidence      BOOL,
  held_with_no_sale          BOOL,
  good_side_no_sale          BOOL,
  -- v27.147: the guard's clock and P-14c's last-day test, as the judge published them
  hold_since                 DATE,
  hold_settles_on            DATE,
  hold_expired               BOOL,
  last_day_sp                FLOAT64,
  last_day_clk               INT64,
  last_day_ord               INT64,
  last_day_gp                FLOAT64,
  last_day_gp_corrected      FLOAT64,
  last_day_ret               FLOAT64,
  last_day_strong            BOOL,
  guard_released_by          STRING,
  -- v27.154 follow-up: the P-14c rule the row was judged under (NULL on rows written before the
  -- columns existed)
  strong_day_mult            FLOAT64,
  strong_day_min_orders      INT64,
  -- v27.156: the judge's memory (P-17, P-18, P-29); NULL on rows written before the columns existed
  hold_strong_day            DATE,
  hold_kept_by               STRING,
  grace_since                DATE,
  memory_cleared_by_gap      STRING,
  rank_no                    INT64,
  seat_no                    INT64,
  seat_cost_per_day          FLOAT64,
  current_bid                FLOAT64,
  planned_bid                FLOAT64,
  bid_floor                  FLOAT64,
  bid_park                   FLOAT64,
  bid_park_source            STRING,
  bid_park_seat_econ         FLOAT64,
  move                       STRING,
  planned_spend_per_day      FLOAT64,
  -- v27.137: planned minus current, per day. A seat's cost is its spend AT THE REPAIRED PRICE
  -- (P-6), and a repair can be a RAISE — so the plan can add money to the not-good side while
  -- staying inside the allowance. This column is that number on the row, so the direction never
  -- has to be inferred from prose.
  planned_spend_delta_per_day FLOAT64,
  verdict_date               DATE,
  pot_per_day                FLOAT64,
  allowance_target_per_day   FLOAT64,
  allowance_ramped_per_day   FLOAT64,
  notgood_today_per_day      FLOAT64,
  ramp_step                  INT64,
  ramp_steps                 INT64,
  allowance_share            FLOAT64,
  campaign_planned_budget    FLOAT64,
  campaign_current_budget    FLOAT64,
  -- v27.138: the campaign cap moves too, and it is the larger number. planned minus current, and
  -- the reason the plan gives for the move — RAMPED (the one-third step), FLOORED_AT_NEED (the
  -- step would have gone under the money the plan can SEE inside the campaign), NO_MOVE_UNMEASURED
  -- (no spend and no clicks on any keyword the plan can see: unmeasured never reads as bad) or
  -- NO_MOVE_BRAND_DEFENSE (defense is never judged on profit, spec §8).
  campaign_planned_budget_delta_per_day FLOAT64,
  campaign_budget_basis      STRING,
  campaign_visible_spend_per_day FLOAT64,
  holdout                    BOOL,
  holdout_member             BOOL,
  holdout_eligible_from      DATE,
  sentence                   STRING,
  built_at                   TIMESTAMP,
  -- v27.158 (P-22, audit fix #15): per family, the not-good spend expected after the upload (the
  -- seats + the queue at the price the plan leaves it at), the share of the gap to the allowance
  -- target that closes (NULL when there is no gap), and the plan uploads that landed since the
  -- family's first plan night (ramp_step = LEAST(ramp_steps, plan_uploads_landed))
  expected_after_upload_per_day FLOAT64,
  share_closed               FLOAT64,
  plan_uploads_landed        INT64,
  -- v27.159 (P-16, P-25): the seat's tenure and the probe flag — seat_since (the night the keyword
  -- took the seat it holds; carried for an incumbent), seat_tenure (INCUMBENT | NEW |
  -- LEFT_ALLOWANCE_SHRANK | NULL) and is_probe (the judge's LIFT nomination flag)
  seat_since                 DATE,
  seat_tenure                STRING,
  is_probe                   BOOL
)
PARTITION BY as_of
CLUSTER BY plan, family, campaign_id
OPTIONS (description = "v27.135 (2026-08-23) the next-week money plan, one row per (as_of, plan, campaign, keyword) for the working families (HARVEST book). Two plans every night: 'B' is live (the window decides the side and the amount, rule B) and 'A' is shadow (the ladder decides the side, the window decides the amount) — spec P-9. Carries the window and its record raw AND corrected for settle completion, the arm that decided the side (settle_arm / decided_by, spec P-14), the family's pot / allowance / ramp step, the seat number and seat cost, the planned price and the executable move, the campaign budget the plan implies, and the plain sentence a person reads. Append-only; the builder rewrites only today's partition. Created empty by Task 1 because V_PLAN_WINDOW_JUDGMENT reads it back as the plan's MEMORY: `side` is the P-14b guard's \"was good\" once a keyword has been judged here (the ladder is only the bootstrap for a keyword the plan has never seen) and `verdict = GRACE` marks the one quiet window P-5 buys as spent, so another is refused until the keyword earns a GOOD window back (the limit reads this table's whole history). Until the builder writes its first row neither memory exists: the guard falls back to the ladder bootstrap and grace_limit_armed is FALSE on every judgement row, which the row says in words. Written by written by SP_BUILD_NEXT_WEEK_PLAN (orchestrator 20.8c); read by SP_SNAPSHOT_ENGINE_PROPOSALS, V_PLAN_SCORECARD, tools/build_plan_bulksheet.py and T_PLAN_NEXT_WEEK. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md. SOP: architecture/NEXT_WEEK_MONEY.md");

-- CREATE TABLE IF NOT EXISTS is a SILENT NO-OP against a table that already exists, so a column
-- added after the first deploy has to be applied explicitly or the file and the warehouse drift.
-- v27.137 adds planned_spend_delta_per_day: planned minus current spend per day, so a repair that
-- RAISES a keyword's spend (a seat costs its spend AT THE REPAIRED PRICE, P-6, and the repaired
-- price can be above today's bid) is readable as a number and not only as prose.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS planned_spend_delta_per_day FLOAT64;

-- v27.138 adds the campaign cap's own disclosure. The keyword raise got a column and a sentence in
-- v27.137; the campaign budget moved on EVERY campaign in the same partition with neither. It is
-- the larger number of the two, and a cap is executable in a way a keyword bid is not — it can
-- starve keywords the plan never judged.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS campaign_planned_budget_delta_per_day FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS campaign_budget_basis STRING;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS campaign_visible_spend_per_day FLOAT64;

-- v27.146 (2026-08-25, plan step 4) — THE SEAT NAMES ITS QUESTION (violation 27, §3.0 step 2).
-- Shipped as scripts/bigquery/migrations/2026-08-25_plan_seat_click_target.sql; mirrored here
-- because this file is CREATE TABLE IF NOT EXISTS and never alters a live table.
-- Nothing here is a forecast. An ORDINARY seat asks for exactly last window's clicks (w_clk),
-- because the seat is that window's spend at a repaired price and the price ratio cancels — it
-- asks for the same clicks at a better price, not for more. A PROBE asks click_goal_day x
-- window_days, a goal the seat register already declares.
-- clicks_due_date is the seat's own verdict_date (P-12), NOT window_to: window_to closes the
-- window that was JUDGED and is in the past, and using it made every request overdue on the day it
-- was written (caught by acceptance S08 on all 94 seats).
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS clicks_requested INT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS clicks_due_date DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS expected_cpc FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS implied_daily_spend FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS request_basis STRING;

-- v27.147 (2026-09-28) — P-14c AND THE GUARD'S RELEASE REASON. Shipped as
-- scripts/bigquery/migrations/2026-09-28_plan_guard_release.sql; mirrored here because this
-- file never alters a live table. The judge's hold clock (hold_since / hold_settles_on /
-- hold_expired, v27.138) is now carried on the row, with the last complete day's own record
-- (last_day_*), whether it was VERY GOOD (last_day_strong, P-14c) and guard_released_by -- the
-- judge's reason for demoting a keyword that was good, served and sits on an unsettled window
-- (LAST_DAY_NOT_STRONG or HOLD_EXPIRED). The builder asserts that reason is present rather than
-- re-deriving the guard, which is how it refused every partition from 2026-08-29 to 2026-09-28.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_since DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_settles_on DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_expired BOOL;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_sp FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_clk INT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_ord INT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_gp FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_gp_corrected FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_ret FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS last_day_strong BOOL;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS guard_released_by STRING;

-- v27.154 follow-up (2026-10-01) — THE RULE EACH ROW WAS JUDGED UNDER. Shipped as
-- scripts/bigquery/migrations/2026-10-01_plan_strong_day_rule_columns.sql; mirrored here. The
-- judge's P-14c settings (strong_day_mult, strong_day_min_orders in its k CTE), as published on the
-- row and copied by the builder, so FN_PLAN_SCORECARD grades each hold and release against the
-- multiplier that decision was made under and never against today's. NULL on the partitions
-- written before the columns existed (2026-09-28 .. 10-01); no existing row is updated.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS strong_day_mult FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS strong_day_min_orders INT64;

-- v27.156 (2026-10-02) — THE JUDGE'S MEMORY. Shipped as
-- scripts/bigquery/migrations/2026-10-02_plan_judge_memory_columns.sql; mirrored here. Piece-1
-- plan Task 2, Ori's rulings R3/R4/R16 = spec P-17/P-18/P-29: hold_strong_day (the very good day
-- that started the hold run), hold_kept_by (LAST_DAY | STRONG_DAY_IN_WINDOW, NULL unless HELD),
-- grace_since (the first night of the grace run) and memory_cleared_by_gap (GRACE | HOLD |
-- GRACE_AND_HOLD — read back by V_PLAN_WINDOW_JUDGMENT as a reset, so it is memory, not a report).
-- NULL on the partitions written before the columns existed; no existing row is updated.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_strong_day DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS hold_kept_by STRING;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS grace_since DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS memory_cleared_by_gap STRING;

-- v27.158 (2026-10-02) — THE FAMILY'S REALISED CUT AND THE UPLOADS THAT LANDED. Shipped as
-- scripts/bigquery/migrations/2026-10-02_plan_money_columns.sql; mirrored here. Piece-1 plan
-- Task 4, Ori's ruling R8 = spec P-22 (expected_after_upload_per_day, share_closed) and audit fix
-- #15 (plan_uploads_landed: ramp_step counts uploads that landed, not windows on the calendar).
-- NULL on the partitions written before the columns existed; no existing row is updated.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS expected_after_upload_per_day FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS share_closed FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS plan_uploads_landed INT64;

-- v27.159 (2026-10-02) — THE SEAT'S TENURE AND THE PROBE FLAG. Shipped as
-- scripts/bigquery/migrations/2026-10-02_plan_seat_tenure_columns.sql; mirrored here. Piece-1
-- plan Task 5, Ori's rulings R2 / R12 of 2026-10-02 = spec P-16 / P-25: seat_since (the night the
-- keyword took the seat it holds — as_of for a new seat, carried for an incumbent; the builder
-- reads it back, and only a seat written with it is an incumbent the next night), seat_tenure
-- (INCUMBENT | NEW | LEFT_ALLOWANCE_SHRANK | NULL) and is_probe (the judge's LIFT nomination flag,
-- so OPEN_PROBE and an unseated probe's NONE are checked without re-deriving who is a probe).
-- NULL on the partitions written before the columns existed; no existing row is updated.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS seat_since DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS seat_tenure STRING;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS is_probe BOOL;
