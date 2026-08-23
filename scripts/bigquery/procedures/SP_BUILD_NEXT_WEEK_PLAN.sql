-- =============================================================================================
-- SP_BUILD_NEXT_WEEK_PLAN — v27.136 (2026-08-23): the nightly plan for the working families.
-- Reads V_PLAN_WINDOW_JUDGMENT (the side and the price) ONCE and turns it into money:
--   1. POT (P-2)        the GOOD side's window spend per day, per family. Not the family total.
--   2. ALLOWANCE (P-2)  allowance_share x pot, from DE_PLAN_CONFIG for today's calendar state.
--   3. RAMP (P-8)       one third of the gap between today's not-good spend and the allowance is
--                       closed each window, so a family several times over the line is not parked
--                       in one upload. Recomputed from actual spend every night, so it converges
--                       whether or not anyone uploads on schedule.
--   4. SEATS (P-6, P-7) not-good CANDIDATES ranked by dollars at stake x closeness to the bar,
--                       each costing its spend AT THE REPAIRED PRICE, taking numbered seats while
--                       the running cost fits the ramped allowance. A continuing occupant keeps
--                       its number from DE_FAMILY_SEAT_LEDGER; a new occupant takes the family's
--                       lowest free number, in rank order.
--   5. QUEUE (§4.5)     every candidate that did not fit: parked at the engine's park price, or
--                       paused when it is already there. Planned spend zero — see the note.
--   6. MOVES (§4.6)     one executable instruction per CANDIDATE; none on the good side, and none
--                       on a not-good keyword with nothing to repair (§9, v27.135).
--   7. BUDGETS (§4.7)   a campaign's planned budget = the sum of its keywords' planned spend,
--                       ramped from today's budget by the same one-third step, floored at the
--                       campaign's own GOOD-side spend (a budget under the good side is a cut,
--                       and P-4 forbids cuts), snapped out of the forbidden $20.01-$31.99 band,
--                       floored at Amazon's $1.00 minimum.
-- BOTH PLANS ARE WRITTEN (P-9): 'B' is live (rule B decides the side), 'A' is the shadow (the
-- ladder decides the side, the window decides the amount). The scorecard grades both at T+14.
--
-- WHY THIS PROCEDURE IS A DOCTRINE DELIVERABLE AND NOT A REPORT. V_PLAN_WINDOW_JUDGMENT reads
-- this table back as the plan's MEMORY: `side` on the live rows is the P-14b guard's "was good"
-- from tomorrow onwards (the ladder is only the bootstrap for a keyword the plan has never seen),
-- and `verdict = 'GRACE'` is what SPENDS P-5's one quiet window. Writing the first partition ARMS
-- the grace limit that has been unenforceable since Task 1 — so GRACE is written as GRACE and is
-- never collapsed into GOOD, and the side is written from the same expression the view publishes.
-- C13 of the acceptance asserts the live plan reproduces the view row for row on side, verdict and
-- candidacy, precisely so no future edit here can quietly re-grant a permanent exemption.
--
-- THE QUEUED-SPEND NOTE. Parking lowers a keyword's price; it does not stop its spend (the seat
-- register's measured ruling R-l). This procedure follows the spec's arithmetic — a queued row's
-- planned spend is zero, so seats + queued = the not-good side and seats <= allowance both hold
-- to the cent — and says so in words on the row, so nobody reads "queued" as "stopped".
--
-- FOUR READINGS THIS BUILDER HAD TO MAKE, each recorded for Ori (SOP §3, "What Ori still rules"):
--   (a) THE HOLDOUT IS OUTSIDE THE MONEY, not only outside the sheet. A holdout campaign's spend
--       is excluded from the pot, from the not-good side and from the ramp base: the plan plans
--       what it owns, and a measurement control's money is not the plan's money to allocate. It
--       still gets a row, a side and a sentence — the counterfactual — and no move. (Zero rows are
--       eligible before 2026-09-01, so this reading costs nothing today and everything later.)
--   (b) A NOT-GOOD KEYWORD WITH NOTHING TO REPAIR GETS NO MOVE. Spec §9 (v27.135): a keyword with
--       no spend, no clicks and no probe nomination takes no seat AND no queue position. Parking
--       a keyword that spends nothing saves nothing, and it would bury the ranking. move = 'NONE'.
--   (c) PLAN A CANNOT ALWAYS BE PRICED. P-4 makes the judgement view withhold planned_bid and
--       seat_cost_per_day wherever rule B calls the row GOOD (C14 of Task 1). Some of those rows
--       are NOT good to the ladder, so the SHADOW plan wants to price a keyword the LIVE plan
--       protects. Rather than compute the repaired price a second time — the "one keyword, two
--       prices" defect — the shadow holds such a row at its current price and costs its seat at
--       its current spend per day, and the row says so. This touches plan A only; plan A is never
--       uploaded. If Ori wants the shadow priced properly, the one-line fix is in the judgement
--       view (publish the unmasked price under a second name), never here.
--   (d) THE IMPLIED BUDGET SEES ONLY THE PLAN'S OWN KEYWORDS. Brand defense, launch-contained and
--       non-keyword targets are outside the universe (§8), so a campaign that mixes them has an
--       implied budget below its real need. That is why the budget is RAMPED from today's budget
--       rather than set to the implied figure, and floored at the campaign's good-side spend.
--
-- Idempotent: deletes today's as_of partition and rewrites it. Never touches an earlier one.
-- Deterministic: every ordering reaches the keyword key.
-- Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c, after the seat ledger (20.8b).
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §4, §5, §9.
-- Acceptance: scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql
-- SOP: architecture/NEXT_WEEK_MONEY.md §3.
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN`()
OPTIONS (description = "v27.136 (2026-08-23): builds the next-week money plan for the HARVEST families and writes today's partition of FACT_PLAN_NEXT_WEEK, both plans (P-9). Reads V_PLAN_WINDOW_JUDGMENT once. Pot = the GOOD side's window spend per day (P-2); allowance = allowance_share x pot from DE_PLAN_CONFIG, ramped one third of the gap to today's not-good spend each window (P-8); not-good CANDIDATES are ranked by dollars at stake x closeness to the bar (P-7) and take numbered dollar-sized seats costing their spend at the repaired price (P-6) until the ramped allowance is full, the rest queue at the engine park price or are paused; one move per candidate, none on the good side (P-4) and none on a not-good keyword with nothing to repair (spec §9); every repriced seat carries a verdict date (P-12); campaign budgets are the sum of planned spend, ramped, floored at the campaign's own good-side spend, snapped out of the forbidden $20.01-$31.99 band and floored at $1.00. Writing this table ARMS P-5's one-window grace limit and becomes the P-14b guard's memory, so GRACE is written as GRACE and never collapsed into GOOD. A holdout campaign's money is excluded from the pot, the not-good side and the ramp, and its row carries the counterfactual and no move. A queued row's planned spend is zero by the spec's arithmetic; the row says in words that parking lowers a price and does not stop a spend. Idempotent on one pass, deterministic. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c. Spec §4, §5, §9. SOP: architecture/NEXT_WEEK_MONEY.md §3")
BEGIN
  DECLARE as_of_d DATE DEFAULT CURRENT_DATE('America/Los_Angeles');
  DECLARE live_plan_code STRING DEFAULT 'B';

  -- The ramp STEP is a report on how long this family has been planned for. Read BEFORE the
  -- delete, so the INSERT never reads the table it is writing.
  CREATE OR REPLACE TEMP TABLE first_seen AS
  SELECT family, MIN(as_of) AS first_as_of
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of < as_of_d
  GROUP BY 1;

  -- ONE scan of the judgement view; everything below reads this copy.
  CREATE OR REPLACE TEMP TABLE j AS
  SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;

  -- Which plan is live comes from the judgement view's own DE_PLAN_CONFIG read, so the builder and
  -- the judge can never disagree about it (one source, not two).
  SET live_plan_code = COALESCE((SELECT MAX(live_plan) FROM j), 'B');

  -- Both plans over the same keywords: 'B' takes rule B's side, 'A' takes the ladder's (P-9).
  -- Candidacy is the view's own expression with the PLAN's side substituted, so for plan B it is
  -- the view's is_candidate exactly (C13 asserts it).
  CREATE OR REPLACE TEMP TABLE r AS
  SELECT j.*,
         pl AS plan,
         IF(pl = 'B', j.side_b, j.side_a) AS side,
         (IF(pl = 'B', j.side_b, j.side_a) = 'NOT_GOOD'
          AND NOT j.holdout
          AND (j.verdict != 'NOT_SERVING' OR j.is_probe))                       AS is_cand,
         -- reading (c): the shadow wants to price a row the live plan protects under P-4
         (pl = 'A' AND j.side_a = 'NOT_GOOD' AND j.side_b = 'GOOD')             AS shadow_unpriced
  FROM j, UNNEST(['A', 'B']) AS pl;

  CREATE OR REPLACE TEMP TABLE r2 AS
  SELECT r.*,
    CASE WHEN r.side = 'GOOD'     THEN NULL              -- P-4: no price on the good side
         WHEN r.shadow_unpriced   THEN r.current_bid     -- reading (c)
         ELSE r.planned_bid END                                     AS plan_bid,
    CASE WHEN r.side = 'GOOD'     THEN NULL              -- P-4: no seat cost on the good side
         WHEN r.shadow_unpriced   THEN COALESCE(SAFE_DIVIDE(r.w_sp, r.window_days), 0)
         ELSE COALESCE(r.seat_cost_per_day, 0) END                   AS plan_seat_cost
  FROM r;

  -- 1-3. Pot, allowance, ramp — per plan x family. Reading (a): the holdout is outside the money.
  CREATE OR REPLACE TEMP TABLE fam AS
  SELECT plan, family,
         MAX(window_days)     AS window_days,
         MAX(allowance_share) AS allowance_share,
         MAX(ramp_steps)      AS ramp_steps,
         COALESCE(SAFE_DIVIDE(SUM(IF(side = 'GOOD'     AND NOT holdout, w_sp, 0)), MAX(window_days)), 0) AS pot_per_day,
         COALESCE(SAFE_DIVIDE(SUM(IF(side = 'NOT_GOOD' AND NOT holdout, w_sp, 0)), MAX(window_days)), 0) AS notgood_today_per_day
  FROM r2
  GROUP BY 1, 2;

  CREATE OR REPLACE TEMP TABLE fam2 AS
  SELECT f.*,
         f.allowance_share * f.pot_per_day AS allowance_target_per_day,
         -- P-8: close one third of the gap this window. A family already inside its allowance
         -- gets the full allowance (GREATEST), never a ramp upwards into a bigger loss budget.
         GREATEST(f.allowance_share * f.pot_per_day,
                  f.notgood_today_per_day
                  - (f.notgood_today_per_day - f.allowance_share * f.pot_per_day) / f.ramp_steps)
           AS allowance_ramped_per_day
  FROM fam f;

  -- 4. Rank and walk the candidates (P-7). The ordering reaches the keyword key, so the walk is
  -- deterministic; seat costs are non-negative, so cum_cost is monotone and the fit is a PREFIX.
  CREATE OR REPLACE TEMP TABLE ranked AS
  SELECT r2.plan, r2.family, r2.campaign_id, r2.keyword_id,
         ROW_NUMBER() OVER w AS rank_no,
         SUM(r2.plan_seat_cost) OVER (
           PARTITION BY r2.plan, r2.family
           ORDER BY r2.rank_score DESC, r2.w_clk DESC, r2.campaign_id, r2.keyword_id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_cost
  FROM r2
  WHERE r2.is_cand
  WINDOW w AS (PARTITION BY r2.plan, r2.family
               ORDER BY r2.rank_score DESC, r2.w_clk DESC, r2.campaign_id, r2.keyword_id);

  -- the family's currently open seats — a continuing occupant keeps its number
  CREATE OR REPLACE TEMP TABLE led AS
  SELECT family, CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         MIN(seat_no) AS led_seat_no
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
  WHERE closed_on IS NULL
  GROUP BY 1, 2, 3;

  CREATE OR REPLACE TEMP TABLE seated AS
  SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no,
         -- a ledger number is honoured ONCE per family: if two open ledger rows claim the same
         -- seat, the better-ranked keyword keeps it and the other is treated as a new occupant,
         -- so the "numbered exactly once" guarantee cannot be broken by a ledger inconsistency.
         IF(ROW_NUMBER() OVER (PARTITION BY k.plan, k.family, l.led_seat_no ORDER BY k.rank_no) = 1,
            l.led_seat_no, NULL) AS led_seat_no
  FROM ranked k
  LEFT JOIN led l ON l.family = k.family AND l.campaign_id = k.campaign_id AND l.keyword_id = k.keyword_id
  WHERE k.cum_cost <= (SELECT MAX(f.allowance_ramped_per_day) FROM fam2 f
                       WHERE f.plan = k.plan AND f.family = k.family) + 0.0001;

  -- the free seat numbers, lowest first, and the new occupants that take them in rank order
  CREATE OR REPLACE TEMP TABLE seat_no_map AS
  WITH cnt AS (
    SELECT plan, family, COUNT(*) AS n_seated, COALESCE(MAX(led_seat_no), 0) AS max_occ
    FROM seated GROUP BY 1, 2),
  nums AS (
    SELECT c.plan, c.family, x AS seat_no
    FROM cnt c, UNNEST(GENERATE_ARRAY(1, c.n_seated + c.max_occ)) AS x),
  taken AS (
    SELECT plan, family, led_seat_no AS seat_no FROM seated WHERE led_seat_no IS NOT NULL),
  free AS (
    SELECT n.plan, n.family, n.seat_no,
           ROW_NUMBER() OVER (PARTITION BY n.plan, n.family ORDER BY n.seat_no) AS free_ix
    FROM nums n
    LEFT JOIN taken t ON t.plan = n.plan AND t.family = n.family AND t.seat_no = n.seat_no
    WHERE t.seat_no IS NULL),
  fresh AS (
    SELECT plan, family, campaign_id, keyword_id,
           ROW_NUMBER() OVER (PARTITION BY plan, family ORDER BY rank_no) AS new_ix
    FROM seated WHERE led_seat_no IS NULL)
  SELECT s.plan, s.family, s.campaign_id, s.keyword_id,
         COALESCE(s.led_seat_no, fr.seat_no) AS seat_no
  FROM seated s
  LEFT JOIN fresh n ON n.plan = s.plan AND n.family = s.family
                   AND n.campaign_id = s.campaign_id AND n.keyword_id = s.keyword_id
  LEFT JOIN free fr ON fr.plan = s.plan AND fr.family = s.family AND fr.free_ix = n.new_ix;

  -- 5-6. Assemble every row: side, seat or queue, move, planned price, planned spend, verdict date
  CREATE OR REPLACE TEMP TABLE assembled AS
  SELECT
    r2.*,
    f.pot_per_day, f.allowance_target_per_day, f.allowance_ramped_per_day,
    f.notgood_today_per_day, f.ramp_steps AS fam_ramp_steps,
    k.rank_no,
    m.seat_no,
    CASE
      WHEN r2.side = 'GOOD'                                             THEN 'NONE'
      WHEN r2.holdout                                                   THEN 'NONE_HOLDOUT'
      WHEN NOT r2.is_cand                                               THEN 'NONE'
      WHEN m.seat_no IS NOT NULL
           AND ABS(COALESCE(r2.plan_bid, r2.current_bid, 0) - COALESCE(r2.current_bid, 0)) > 0.005
                                                                        THEN 'REPRICE'
      WHEN m.seat_no IS NOT NULL                                        THEN 'HOLD_AT_PRICE'
      WHEN COALESCE(r2.bid_park, r2.bid_floor, 0) < COALESCE(r2.current_bid, 0) - 0.005 THEN 'PARK'
      ELSE 'PAUSE'
    END AS move
  FROM r2
  JOIN fam2 f USING (plan, family)
  LEFT JOIN ranked k ON k.plan = r2.plan AND k.family = r2.family
                    AND k.campaign_id = r2.campaign_id AND k.keyword_id = r2.keyword_id
  LEFT JOIN seat_no_map m ON m.plan = r2.plan AND m.family = r2.family
                         AND m.campaign_id = r2.campaign_id AND m.keyword_id = r2.keyword_id;

  CREATE OR REPLACE TEMP TABLE priced AS
  SELECT a.*,
    CASE a.move
      WHEN 'REPRICE'       THEN ROUND(a.plan_bid, 2)
      WHEN 'HOLD_AT_PRICE' THEN a.current_bid
      WHEN 'PARK'          THEN ROUND(COALESCE(a.bid_park, a.bid_floor, a.current_bid), 2)
      WHEN 'PAUSE'         THEN a.current_bid
      ELSE NULL
    END AS planned_bid_final,
    CASE
      WHEN a.side = 'GOOD' OR a.holdout OR NOT a.is_cand
                                        THEN COALESCE(SAFE_DIVIDE(a.w_sp, a.window_days), 0)
      WHEN a.seat_no IS NOT NULL        THEN a.plan_seat_cost
      ELSE 0
    END AS planned_spend_per_day,
    IF(a.move = 'REPRICE', DATE_ADD(as_of_d, INTERVAL a.settle_days DAY), NULL) AS verdict_date
  FROM assembled a;

  -- 7. Campaign budgets: sum of planned spend, ramped one step, floored at the campaign's own
  -- good-side spend (P-4), band-snapped and floored at $1.00.
  CREATE OR REPLACE TEMP TABLE budgets AS
  WITH implied AS (
    SELECT plan, campaign_id,
           SUM(planned_spend_per_day)                          AS implied_budget,
           SUM(IF(side = 'GOOD', planned_spend_per_day, 0))     AS good_budget,
           MAX(campaign_current_budget)                        AS current_budget,
           MAX(fam_ramp_steps)                                 AS ramp_steps
    FROM priced GROUP BY 1, 2),
  rampd AS (
    SELECT plan, campaign_id, current_budget, good_budget,
           GREATEST(
             COALESCE(current_budget, implied_budget)
             + (implied_budget - COALESCE(current_budget, implied_budget)) / ramp_steps,
             good_budget, 1.00) AS raw_budget
    FROM implied)
  SELECT plan, campaign_id, current_budget,
         ROUND(
           CASE WHEN raw_budget > 20.00 AND raw_budget < 32.00
                -- never snap a cap BELOW the good side it has to pay for
                THEN IF(raw_budget < 26.00 AND good_budget <= 20.00, 20.00, 32.00)
                ELSE raw_budget END, 2) AS campaign_planned_budget
  FROM rampd;

  DELETE FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d;

  INSERT INTO `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
    (as_of, plan, is_live_plan, family, book, campaign_id, campaign_name, keyword_id, ad_group_id,
     target_text, match_type, channel, is_auto, is_pt, calendar_state, window_days, window_from,
     window_to, watermark, w_clk, w_ord, w_sp, w_gp, w_gp_corrected, settle_factor_min,
     settle_factor_eff, settle_curve_available, settled, settle_due_on, settle_arm, decided_by,
     was_good, family_bar, ret_raw, ret_corrected, ladder_state, side, verdict, is_candidate,
     rank_score, rank_dollars_at_stake, rank_closeness, rank_is_degenerate, served, prior_grace,
     last_grace_on, grace_limit_armed, held_despite_evidence, held_with_no_sale, good_side_no_sale,
     rank_no, seat_no, seat_cost_per_day, current_bid, planned_bid, bid_floor, bid_park,
     bid_park_source, bid_park_seat_econ, move, planned_spend_per_day, verdict_date, pot_per_day,
     allowance_target_per_day, allowance_ramped_per_day, notgood_today_per_day, ramp_step,
     ramp_steps, allowance_share, campaign_planned_budget, campaign_current_budget, holdout,
     holdout_member, holdout_eligible_from, sentence, built_at)
  SELECT
    as_of_d, p.plan, (p.plan = live_plan_code), p.family, p.book, p.campaign_id, p.campaign_name,
    p.keyword_id, p.ad_group_id, p.target_text, p.match_type, p.channel, p.is_auto, p.is_pt,
    p.calendar_state, p.window_days, p.window_from, p.window_to, p.watermark,
    p.w_clk, p.w_ord, p.w_sp, p.w_gp, p.w_gp_corrected,
    p.settle_factor_min, p.settle_factor_eff, p.settle_curve_available, p.settled, p.settle_due_on,
    p.settle_arm, p.decided_by, p.was_good, p.family_bar, p.ret_raw, p.ret_corrected,
    p.ladder_state, p.side, p.verdict, p.is_cand,
    p.rank_score, p.rank_dollars_at_stake, p.rank_closeness,
    (p.is_cand AND p.rank_score = 0), p.served, p.prior_grace, p.last_grace_on,
    p.grace_limit_armed, p.held_despite_evidence, p.held_with_no_sale, p.good_side_no_sale,
    p.rank_no, p.seat_no,
    IF(p.side = 'GOOD', NULL, ROUND(p.plan_seat_cost, 4)),
    p.current_bid, p.planned_bid_final, p.bid_floor, p.bid_park, p.bid_park_source,
    p.bid_park_seat_econ, p.move, ROUND(p.planned_spend_per_day, 4), p.verdict_date,
    ROUND(p.pot_per_day, 4), ROUND(p.allowance_target_per_day, 4),
    ROUND(p.allowance_ramped_per_day, 4), ROUND(p.notgood_today_per_day, 4),
    -- ramp_step is a REPORT: how many windows the plan has been running for this family, capped
    -- at ramp_steps. The arithmetic above does not depend on it — each night's ramp is recomputed
    -- from the actual not-good spend, so the sequence converges with or without an upload.
    LEAST(p.fam_ramp_steps,
          1 + DIV(DATE_DIFF(as_of_d, COALESCE(fs.first_as_of, as_of_d), DAY), p.window_days)),
    p.fam_ramp_steps, p.allowance_share,
    b.campaign_planned_budget, p.campaign_current_budget,
    p.holdout, p.holdout_member, p.holdout_eligible_from,
    CONCAT(
      IF(p.plan = live_plan_code, '', 'SHADOW PLAN A, recorded for grading and never uploaded (P-9). '),
      COALESCE(p.sentence, ''), ' ', COALESCE(p.settle_arm_sentence, ''), '.',
      CASE p.move
        WHEN 'REPRICE' THEN FORMAT(
          ' SEAT %d of %s: re-price $%.2f -> $%.2f, costing about $%.2f a day of the $%.2f a day this family allows the not-good side. Judged again on %t (P-12).',
          COALESCE(p.seat_no, 0), p.family, COALESCE(p.current_bid, 0),
          COALESCE(p.planned_bid_final, 0), COALESCE(p.plan_seat_cost, 0),
          COALESCE(p.allowance_ramped_per_day, 0), COALESCE(p.verdict_date, as_of_d))
        WHEN 'HOLD_AT_PRICE' THEN FORMAT(
          ' SEAT %d of %s: the price is already where the plan wants it, so nothing is uploaded; it keeps its seat at about $%.2f a day of the $%.2f a day this family allows the not-good side.',
          COALESCE(p.seat_no, 0), p.family, COALESCE(p.plan_seat_cost, 0),
          COALESCE(p.allowance_ramped_per_day, 0))
        WHEN 'PARK' THEN FORMAT(
          ' QUEUED at rank %d, no seat: park the bid at $%.2f. Parking LOWERS the price, it does not stop the spend — this keyword keeps buying clicks at the park price until it earns a seat or is killed, so the real not-good spend of this family sits above the $%.2f a day allowance until then.',
          COALESCE(p.rank_no, 0), COALESCE(p.planned_bid_final, 0),
          COALESCE(p.allowance_ramped_per_day, 0))
        WHEN 'PAUSE' THEN FORMAT(
          ' QUEUED at rank %d, no seat, and already at or below the park price: pause it. A keyword that queues a whole window with no seat is a kill candidate (probation unchanged: bid to the floor, probation, then kill).',
          COALESCE(p.rank_no, 0))
        WHEN 'NONE_HOLDOUT' THEN
          ' This campaign is a measurement control: the plan records what it would have done, uploads nothing to it, and leaves its money out of the pot, the not-good side and the ramp.'
        ELSE IF(p.side = 'GOOD',
          ' No move: the good side is never cut and is not re-priced (P-4), and this row carries no planned price and no seat cost.',
          ' No move: there is nothing to repair here — no spend, no clicks and no probe nomination in the window — so this keyword takes neither a seat nor a queue position (spec §9).')
      END,
      IF(p.shadow_unpriced,
         ' SHADOW PRICING NOTE: the live plan calls this keyword GOOD, so P-4 withholds a repaired price for it and the shadow holds it at its current price and costs its seat at its current spend.',
         '')) AS sentence,
    CURRENT_TIMESTAMP()
  FROM priced p
  LEFT JOIN budgets b   ON b.plan = p.plan AND b.campaign_id = p.campaign_id
  LEFT JOIN first_seen fs ON fs.family = p.family;

  -- §9 guarantees, asserted where they are cheapest to assert: at write time. An assertion failure
  -- names the guarantee it broke — fix the arithmetic, never the assertion.
  ASSERT (SELECT COUNT(DISTINCT plan) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d) = 2
    AS 'both plans must be written every night (P-9)';
  ASSERT (SELECT COUNTIF(side = 'GOOD' AND (move != 'NONE' OR planned_bid IS NOT NULL OR seat_cost_per_day IS NOT NULL))
          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d) = 0
    AS 'the good side is never cut, is not re-priced, and carries no executable price (P-4)';
  ASSERT (SELECT COUNTIF(seat_cost > allowance + 0.01) FROM (
            SELECT plan, family, SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                   MAX(allowance_ramped_per_day) allowance
            FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d GROUP BY 1, 2)) = 0
    AS 'seats must fit the ramped allowance (P-2, P-8)';
  ASSERT (SELECT COUNTIF(side = 'NOT_GOOD' AND was_good AND served AND NOT settled)
          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d AND is_live_plan) = 0
    AS 'no keyword that was good and served in the window may be demoted before it settles (P-14b)';
  ASSERT (SELECT COUNTIF(holdout AND (move NOT IN ('NONE', 'NONE_HOLDOUT') OR seat_no IS NOT NULL))
          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d) = 0
    AS 'a holdout campaign gets a record and no move';
  ASSERT (SELECT COUNTIF(campaign_planned_budget > 20.00 AND campaign_planned_budget < 32.00)
          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d) = 0
    AS 'no campaign budget may sit in the forbidden $20.01-$31.99 band';
END;
