-- =============================================================================================
-- SP_BUILD_NEXT_WEEK_PLAN — v27.147 (2026-09-28): the nightly plan for the working families.
-- Reads V_PLAN_WINDOW_JUDGMENT (the side and the price) ONCE and turns it into money:
--   1. POT (P-2)        the GOOD side's window spend per day, per family. Not the family total.
--   2. ALLOWANCE (P-2)  allowance_share x pot, from DE_PLAN_CONFIG for today's calendar state.
--   3. RAMP (P-8)       one third of the gap between today's not-good spend and the allowance is
--                       closed each window, so a family several times over the line is not parked
--                       in one upload. Recomputed from actual spend every night, so it converges
--                       whether or not anyone uploads on schedule.
--   4. SEATS (P-6, P-7) not-good CANDIDATES ranked by dollars at stake x closeness to the bar,
--                       each costing its spend AT THE REPAIRED PRICE, walked in rank order: a
--                       candidate takes the lowest free seat WHENEVER ITS OWN COST FITS THE
--                       ALLOWANCE STILL UNSPENT (§4.4 — a fit test, not a prefix stop; one lumpy
--                       candidate does not close the queue behind it). A KEYWORD THE LADDER HAS
--                       CLOSED IS NOT SEATABLE AT ANY PRICE (v27.138). A continuing occupant keeps
--                       its number from DE_FAMILY_SEAT_LEDGER, or failing that from LAST NIGHT'S
--                       PLAN (v27.138 — the register only admits ladder occupant states, so half
--                       the plan's seats can never hold a ledger row and were re-numbered nightly
--                       from a rank order that is recomputed every night); a new occupant takes
--                       the family's lowest number neither source is still holding, in rank order.
--   5. QUEUE (§4.5)     every candidate that did not fit: parked at the engine's park price, held
--                       at the price it already has when that is at or below the park price, or
--                       paused when THE LADDER HAS ALREADY CLOSED IT. Planned spend zero — see
--                       the note.
--   6. MOVES (§4.6)     one executable instruction per CANDIDATE; none on the good side, and none
--                       on a not-good keyword with nothing to repair (§9, v27.135).
--   7. BUDGETS (§4.7)   a campaign's planned budget is ramped from today's budget by the same
--                       one-third step and floored at THE MONEY THE PLAN CAN SEE INSIDE THAT
--                       CAMPAIGN — its good side, its seats at the repaired price, AND the queue
--                       that keeps buying clicks at the park price (v27.138: the v27.137 floor
--                       counted the queue at zero, which is the plan's own arithmetic and not the
--                       money, so a campaign whose spend is all queued was ramped towards a figure
--                       the plan's own PARK sentence disowns). NO MOVE AT ALL on a campaign the
--                       plan measured nothing in, or on a brand-defense campaign (v27.138: the
--                       ramp was a one-third step towards zero on 19 unmeasured campaigns, one of
--                       them brand defense, compounding nightly). Then snapped out of the
--                       forbidden $20.01-$31.99 band and floored at Amazon's $1.00 minimum. Every
--                       row publishes the cap's delta, its basis and the visible spend, and says
--                       all three in words — the cap is the largest number here and used to be
--                       the silent one.
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
-- THE QUEUED-SPEND NOTE, CORRECTED (v27.137). Parking lowers a keyword's price; it does not stop
-- its spend (the seat register's measured ruling R-l). This procedure follows the spec's
-- arithmetic — a queued row's PLANNED spend is zero — and says so in words on the row, so nobody
-- reads "queued" as "stopped". But the earlier version of this note claimed that made "seats +
-- queued = the not-good side" hold to the cent, and IT DOES NOT: with the queue at zero the
-- identity that holds is seats = the not-good side's PLANNED spend, while the queue's real spend
-- carries on at the park price and is exactly the residual between the plan and the money. The
-- restatement is in spec §9 and acceptance C19 asserts the identity that is true; whether the
-- arithmetic should instead carry the queue's residual is a one-line ruling recorded for Ori.
-- What still holds unconditionally is seats <= the ramped allowance (P-2, P-8), asserted.
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
--   (d) THE BUDGET SEES ONLY THE PLAN'S OWN KEYWORDS, SO IT IS RAMPED AND FLOORED AND SOMETIMES
--       NOT MOVED AT ALL. Brand defense, launch-contained and non-keyword targets are outside the
--       universe (§8), so a campaign that mixes them looks cheaper to the plan than it is. Ramping
--       only SLOWS a wrong descent; it does not stop one, and a cap the ramp re-reads every night
--       compounds. So v27.138 adds the two floors ramping cannot supply: the cap is never set
--       below the money the plan can SEE inside the campaign (queue included), and a campaign the
--       plan measured nothing in — or a brand-defense campaign — is not moved at all.
--
-- Idempotent: deletes today's as_of partition and rewrites it. Never touches an earlier one.
-- Deterministic: every ordering reaches the keyword key.
-- Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c, after the seat ledger (20.8b).
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §4, §5, §9.
-- Acceptance: scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql
-- SOP: architecture/NEXT_WEEK_MONEY.md §3.
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN`()
OPTIONS (description = "v27.147 (2026-09-28): the P-14b assertion checks the judgement is COMPLETE (guard_released_by present on every demotion under the guard's preconditions; every HELD row on the good side with a very good last day, P-14c) instead of re-deriving the guard as a veto -- the v27.136 form refused every partition from 2026-08-29 to 2026-09-28 once the judge's hold clock first expired. Carries hold_since / hold_settles_on / hold_expired, last_day_* and guard_released_by into the plan table. v27.138 (2026-08-24): builds the next-week money plan for the HARVEST families and writes today's partition of FACT_PLAN_NEXT_WEEK, both plans (P-9). Reads V_PLAN_WINDOW_JUDGMENT once. Pot = the GOOD side's window spend per day (P-2); allowance = allowance_share x pot from DE_PLAN_CONFIG, ramped one third of the gap to today's not-good spend each window (P-8); not-good CANDIDATES are ranked by dollars at stake x closeness to the bar (P-7) and walked in rank order, each taking a numbered dollar-sized seat costing its spend at the repaired price (P-6) WHENEVER ITS OWN COST FITS THE ALLOWANCE STILL UNSPENT (spec 4.4 is a fit test, not a prefix stop), the rest queueing at the engine park price, held at a price already at or below it, or paused when the ladder has already closed them; seat numbers come from DE_FAMILY_SEAT_LEDGER and a number the register still holds OPEN is never reissued; one move per candidate, none on the good side (P-4) and none on a not-good keyword with nothing to repair (spec 9); EVERY SEAT carries a verdict date, held or repriced (P-12); every row publishes planned_spend_delta_per_day, so a repair that RAISES a keyword's spend says so in a column; campaign budgets are the sum of planned spend, ramped, floored at the spend the plan itself planned inside the campaign, snapped out of the forbidden $20.01-$31.99 band and floored at $1.00. Every guarantee is ASSERTed on a temp table BEFORE the partition is touched, so a broken build leaves yesterday's plan standing. Writing this table ARMS P-5's one-window grace limit and becomes the P-14b guard's memory, so GRACE is written as GRACE and never collapsed into GOOD. A holdout campaign's money is excluded from the pot, the not-good side and the ramp, and its row carries the counterfactual and no move. A queued row's planned spend is zero by the spec's arithmetic; the row says in words that parking lowers a price and does not stop a spend. Idempotent on one pass, deterministic. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c. Spec 4, 5, 9. SOP: architecture/NEXT_WEEK_MONEY.md 3")
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
         -- P-8 RAMPS DOWNWARDS AND NOT UPWARDS, AND THE GREATEST IS WHY (comment corrected
         -- v27.138 — the previous one said the opposite of what this line does). The ramp term
         -- alone closes one third of the gap between today's not-good spend and the allowance, in
         -- whichever direction the gap runs. The GREATEST removes the DOWNWARD half of that for a
         -- family already inside its allowance: instead of being ramped up one third at a time
         -- towards the allowance, it is handed THE WHOLE ALLOWANCE ON NIGHT ONE. So the GREATEST
         -- does not protect a family from a bigger loss budget — it GRANTS one immediately, and a
         -- family whose allowance exceeds its entire not-good side (LolliME on the first
         -- partition; SOP §3 publishes the query) is rationed by nothing: every candidate fits,
         -- and P-6's repaired price can then RAISE the family's not-good spend.
         -- That consequence is on the row (planned_spend_delta_per_day, and the seat sentence
         -- prints the direction) and per family in the SOP. Whether a seat may raise at all is
         -- one of the rulings recorded for Ori; the arithmetic here is the spec's, unchanged.
         GREATEST(f.allowance_share * f.pot_per_day,
                  f.notgood_today_per_day
                  - (f.notgood_today_per_day - f.allowance_share * f.pot_per_day) / f.ramp_steps)
           AS allowance_ramped_per_day
  FROM fam f;

  -- 4. Rank the candidates (P-7). The ordering reaches the keyword key, so the walk below is
  -- deterministic on any re-run.
  -- A KEYWORD THE LADDER HAS CLOSED IS NOT SEATABLE (v27.138). It still gets a rank and a queue
  -- position — every candidate has exactly one of a seat or a queue position (§9) — but it can
  -- never take a seat, hold family allowance or be published with a price. v27.137 tested DEAD
  -- only AFTER the two seat branches of the move CASE, so whether a closed keyword was stopped or
  -- re-priced was decided by whether its cost happened to fit: on the first partition ten closed
  -- keywords took seats and were published with an executable bid while a single closed keyword
  -- that did not fit was told "a closed keyword is stopped, not re-priced". Two opposite
  -- instructions from one ladder state in one partition. Deciding it here rather than only in the
  -- move CASE is what makes it true of the MONEY as well as of the words: a closed keyword no
  -- longer consumes allowance a repairable keyword could have used.
  CREATE OR REPLACE TEMP TABLE ranked AS
  SELECT r2.plan, r2.family, r2.campaign_id, r2.keyword_id,
         ROW_NUMBER() OVER w AS rank_no,
         COALESCE(r2.plan_seat_cost, 0) AS cost,
         (r2.ladder_state = 'DEAD') AS is_closed
  FROM r2
  WHERE r2.is_cand
  WINDOW w AS (PARTITION BY r2.plan, r2.family
               ORDER BY r2.rank_score DESC, r2.w_clk DESC, r2.campaign_id, r2.keyword_id);

  -- THE WALK IS A FIT TEST, NOT A PREFIX STOP (spec §4.4, repaired v27.137). "A candidate takes
  -- the lowest free seat WHILE ITS COST FITS THE REMAINING ALLOWANCE" is per candidate: one lumpy
  -- candidate must not close the queue behind it. v27.136 filtered on a running prefix sum
  -- (cum_cost <= allowance), which halted each family's seating at the first candidate that did
  -- not fit and parked every cheaper candidate below it — cutting harder than P-8's ramp intends,
  -- on exactly the lumpy distributions P-8 exists for, and leaving a large part of the ramped
  -- allowance unassigned. Measured on the deployed v27.136 partition before this repair: three
  -- plan x family walks left a queued candidate that fitted the allowance they had not spent
  -- (acceptance C18, red before and green after).
  -- Skip-and-continue is exactly as deterministic as a prefix: the ranking is a total order down
  -- to the keyword key, and the recursion follows it one rank at a time. The invariant it leaves
  -- behind is checkable — every queued candidate costs more than the allowance the family ends
  -- with, because the remaining allowance only ever falls as the walk proceeds.
  CREATE OR REPLACE TEMP TABLE walk AS
  WITH RECURSIVE w AS (
    SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no, k.cost,
           f.allowance_ramped_per_day AS allow,
           (NOT k.is_closed AND k.cost <= f.allowance_ramped_per_day + 0.0001) AS took,
           IF(NOT k.is_closed AND k.cost <= f.allowance_ramped_per_day + 0.0001, k.cost, 0.0) AS spent
    FROM ranked k
    JOIN fam2 f ON f.plan = k.plan AND f.family = k.family
    WHERE k.rank_no = 1
    UNION ALL
    SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no, k.cost,
           w.allow,
           (NOT k.is_closed AND w.spent + k.cost <= w.allow + 0.0001),
           w.spent + IF(NOT k.is_closed AND w.spent + k.cost <= w.allow + 0.0001, k.cost, 0.0)
    FROM w
    JOIN ranked k ON k.plan = w.plan AND k.family = w.family AND k.rank_no = w.rank_no + 1
  )
  SELECT * FROM w;

  -- the family's currently open seats — a continuing occupant keeps its number
  CREATE OR REPLACE TEMP TABLE led AS
  SELECT family, CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         MIN(seat_no) AS led_seat_no
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
  WHERE closed_on IS NULL
  GROUP BY 1, 2, 3;

  -- THE PLAN'S OWN LAST PARTITION IS THE SECOND SOURCE OF CONTINUITY (v27.138). §9 promises "seat
  -- numbers stable across days for continuing occupants", and the ledger alone cannot deliver it:
  -- SP_MAINTAIN_FAMILY_SEATS admits only LADDER occupant states, so a keyword the PLAN seats whose
  -- ladder state the register closes (AT_BAR closes TO_GOOD_SIDE, DEAD closes KILLED) never
  -- acquires an open ledger row and, on v27.137, was handed a fresh number every night from an
  -- index into THAT NIGHT'S rank order — which is recomputed from the window nightly. Half the
  -- first partition's seats were in that position, so "SEAT 52 of LolliME" named a different
  -- keyword from one night to the next and nothing could see it: C05 checks uniqueness inside one
  -- partition and C17 checks non-collision with the register.
  -- The precedence is register > last night's plan > lowest free number. The register still wins,
  -- because it is the authority Ori's vocabulary comes from; last night's plan only fills the gap
  -- the register leaves, and only with a number the register is not holding open for anyone else.
  CREATE OR REPLACE TEMP TABLE prior_plan AS
  WITH h AS (
    SELECT plan, family, CAST(campaign_id AS STRING) AS campaign_id,
           CAST(keyword_id AS STRING) AS keyword_id, seat_no, as_of,
           MAX(as_of) OVER (PARTITION BY plan) AS last_as_of
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
    WHERE as_of < as_of_d AND seat_no IS NOT NULL)
  SELECT plan, family, campaign_id, keyword_id, MIN(seat_no) AS prior_seat_no
  FROM h WHERE as_of = last_as_of
  GROUP BY 1, 2, 3, 4;

  CREATE OR REPLACE TEMP TABLE seated AS
  WITH c AS (
    SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no,
           l.led_seat_no,
           -- last night's number is only a claim if the register is not holding it for someone else
           IF(pp.prior_seat_no IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM led l2
                              WHERE l2.family = k.family AND l2.led_seat_no = pp.prior_seat_no),
              pp.prior_seat_no, NULL) AS prior_seat_no
    FROM walk k
    LEFT JOIN led l  ON l.family = k.family AND l.campaign_id = k.campaign_id
                    AND l.keyword_id = k.keyword_id
    LEFT JOIN prior_plan pp ON pp.plan = k.plan AND pp.family = k.family
                           AND pp.campaign_id = k.campaign_id AND pp.keyword_id = k.keyword_id
    WHERE k.took)
  SELECT plan, family, campaign_id, keyword_id, rank_no, led_seat_no,
         -- a number is honoured ONCE per family: if two rows claim the same seat, the REGISTER's
         -- claimant keeps it and the other is treated as a new occupant, so the "numbered exactly
         -- once" guarantee cannot be broken by an inconsistency in either source.
         IF(ROW_NUMBER() OVER (PARTITION BY plan, family, COALESCE(led_seat_no, prior_seat_no)
                               ORDER BY (led_seat_no IS NULL), rank_no) = 1,
            COALESCE(led_seat_no, prior_seat_no), NULL) AS kept_seat_no
  FROM c;

  -- the free seat numbers, lowest first, and the new occupants that take them in rank order
  -- SEAT NUMBERS ARE THE REGISTER'S, NOT THE PLAN'S (§9, repaired v27.137). A number is FREE only
  -- when the ledger has freed it — closed_on IS NOT NULL. v27.136 built the occupied set from the
  -- keywords THIS RUN seated, so any open ledger seat whose occupant the plan did not seat
  -- tonight (it turned GOOD, it queued, it stopped being a candidate) read as free and was handed
  -- to a new occupant, splitting the register into two disagreeing authorities — the plan
  -- publishing "SEAT 1 of LolliME" for one keyword while the ledger held seat 1 open for another.
  -- Measured on the deployed v27.136 partition before this repair: acceptance C17, red before and
  -- green after. The pool is widened to n_seated + the family's highest OPEN ledger number, which
  -- always leaves at least n_seated free numbers however many the register is holding.
  CREATE OR REPLACE TEMP TABLE seat_no_map AS
  WITH cnt AS (
    SELECT plan, family, COUNT(*) AS n_seated FROM seated GROUP BY 1, 2),
  ledmax AS (
    SELECT family, MAX(led_seat_no) AS max_led FROM led GROUP BY 1),
  keptmax AS (
    SELECT plan, family, MAX(kept_seat_no) AS max_kept FROM seated GROUP BY 1, 2),
  nums AS (
    SELECT c.plan, c.family, x AS seat_no
    FROM cnt c
    LEFT JOIN ledmax lm ON lm.family = c.family
    LEFT JOIN keptmax km ON km.plan = c.plan AND km.family = c.family,
    UNNEST(GENERATE_ARRAY(
      1, c.n_seated + GREATEST(COALESCE(lm.max_led, 0), COALESCE(km.max_kept, 0)))) AS x),
  -- occupied = every number the REGISTER still holds open for this family, plus every number a
  -- continuing occupant kept tonight. Both must be excluded or a new occupant takes a number that
  -- is already somebody's.
  taken AS (
    SELECT c.plan, c.family, l.led_seat_no AS seat_no
    FROM cnt c JOIN led l ON l.family = c.family
    UNION DISTINCT
    SELECT plan, family, kept_seat_no FROM seated WHERE kept_seat_no IS NOT NULL),
  free AS (
    SELECT n.plan, n.family, n.seat_no,
           ROW_NUMBER() OVER (PARTITION BY n.plan, n.family ORDER BY n.seat_no) AS free_ix
    FROM nums n
    LEFT JOIN taken t ON t.plan = n.plan AND t.family = n.family AND t.seat_no = n.seat_no
    WHERE t.seat_no IS NULL),
  fresh AS (
    SELECT plan, family, campaign_id, keyword_id,
           ROW_NUMBER() OVER (PARTITION BY plan, family ORDER BY rank_no) AS new_ix
    FROM seated WHERE kept_seat_no IS NULL)
  SELECT s.plan, s.family, s.campaign_id, s.keyword_id,
         COALESCE(s.kept_seat_no, fr.seat_no) AS seat_no,
         CASE WHEN s.led_seat_no IS NOT NULL  THEN 'REGISTER'
              WHEN s.kept_seat_no IS NOT NULL THEN 'PLAN_CONTINUITY'
              ELSE 'NEW_LOWEST_FREE' END AS seat_no_source
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
      -- §4.5: "parked at the channel park price OR PAUSED IF ALREADY CLOSED". Closed is the
      -- ladder's own DEAD state, not "the park price is not below the current bid" — v27.136 read
      -- the second and paused serving keywords on their FIRST window in the queue, against §4.5's
      -- own kill ladder (bid to the floor, probation, then kill).
      -- CLOSED IS TESTED BEFORE THE SEAT (v27.138), not merely before parking. "The stronger of
      -- the two instructions, not the fallback" was written of parking in v27.137 and then placed
      -- BELOW both seat branches, so on the first partition ten closed keywords were seated and
      -- re-priced while one was stopped — the difference being only whether the cost fitted. The
      -- walk above already refuses them a seat, so this branch can never be shadowed again.
      WHEN r2.ladder_state = 'DEAD'                                     THEN 'PAUSE'
      WHEN m.seat_no IS NOT NULL
           AND ABS(COALESCE(r2.plan_bid, r2.current_bid, 0) - COALESCE(r2.current_bid, 0)) > 0.005
                                                                        THEN 'REPRICE'
      WHEN m.seat_no IS NOT NULL                                        THEN 'HOLD_AT_PRICE'
      WHEN COALESCE(r2.bid_park, r2.bid_floor, 0) < COALESCE(r2.current_bid, 0) - 0.005 THEN 'PARK'
      -- a queued keyword already at or below its park price has nothing to upload: it holds its
      -- queue position at the price it has, and the probation clock decides when it dies.
      ELSE 'HOLD_AT_PARK'
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
      WHEN 'HOLD_AT_PARK'  THEN a.current_bid
      -- a paused row carries NO price: pause is a state change, and publishing a bid beside it
      -- invites a book generator to upload one on a keyword the plan says to stop.
      ELSE NULL
    END AS planned_bid_final,
    CASE
      WHEN a.side = 'GOOD' OR a.holdout OR NOT a.is_cand
                                        THEN COALESCE(SAFE_DIVIDE(a.w_sp, a.window_days), 0)
      WHEN a.seat_no IS NOT NULL        THEN a.plan_seat_cost
      ELSE 0
    END AS planned_spend_per_day,
    -- P-12 IS ABOUT SEATS, NOT ABOUT REPRICES (repaired v27.137). "Every seat carries a verdict
    -- date: graduate, step again, or give the seat up" — and it exists to stop the queue becoming
    -- a parking lot. A seat HELD AT ITS CURRENT PRICE is precisely the parking-lot case: it holds
    -- allowance and uploads nothing. v27.136 dated only the REPRICE rows and the acceptance froze
    -- that narrowing into a check; both are corrected, and the departure is on the list Ori reads.
    IF(a.seat_no IS NOT NULL, DATE_ADD(as_of_d, INTERVAL a.settle_days DAY), NULL) AS verdict_date
  FROM assembled a;

  -- 7. Campaign budgets. THE CAP IS THE LARGEST EXECUTABLE NUMBER THIS PROCEDURE PUBLISHES, and
  -- v27.137's floor — "the plan's own spend inside the campaign" — was satisfied by construction
  -- rather than by protecting anything, because the plan's own spend is exactly the figure that
  -- counts a queued keyword at zero and a keyword it never judged at nothing at all. Two ways that
  -- became an executable cut on the first partition:
  --   (i)  THE QUEUE'S RESIDUAL STEERED THE BUDGET. A campaign whose money is in the QUEUE implies
  --        almost nothing (queued rows are planned at zero) and was ramped towards that figure,
  --        which the plan's own PARK sentence disowns in words on the same row: parking lowers a
  --        price, it does not stop a spend. One campaign implied $2.56/day against $53.13/day of
  --        spend the plan could see, and its cap was ramped down by a third.
  --   (ii) CAMPAIGNS THE PLAN COULD NOT MEASURE WERE CUT TOWARDS ZERO. 19 campaigns had every
  --        keyword NOT_SERVING with no spend and no clicks in a three-day August window; implied
  --        was 0, so the ramp was a one-third step towards zero — $153.35/day of cuts on evidence
  --        the plan does not have, compounding nightly because the ramp re-reads the cap it wrote
  --        ($150 -> $100 -> $66.67 -> ...). One of them was a BRAND DEFENSE campaign whose five
  --        keywords are the house's own brand terms. That breaks two binding house rules at once:
  --        unmeasured never reads as bad, and brand defense is never judged on profit (§8).
  -- The repair (v27.138) is three parts:
  --   NEED is the money the plan can SEE inside the campaign — its good side, its seats at the
  --   repaired price, AND the queue's continuing spend at today's rate. Parking is expected to
  --   lower that, so using today's rate is deliberately conservative: it can only over-fund.
  --   THE UNMEASURED GATE: a campaign with no spend and no clicks on any keyword the plan can see
  --   gets NO MOVE. The plan has measured nothing there and has nothing to say about its cap.
  --   THE DEFENSE GATE: a brand-defense campaign gets NO MOVE, whatever the window says. Detected
  --   the way the seat register detects it (the ladder flag OR 'BRAND DEFENSE' in the campaign
  --   name) — the ladder flag alone reads FALSE on the live defense campaign, which is why §8's
  --   filter in the judgement view did not catch it. That the flag is wrong is a Task 1 file and
  --   is recorded for Ori, not patched here.
  CREATE OR REPLACE TEMP TABLE budgets AS
  WITH implied AS (
    SELECT plan, campaign_id,
           SUM(planned_spend_per_day)                          AS implied_budget,
           SUM(IF(side = 'GOOD', planned_spend_per_day, 0))    AS good_budget,
           -- the queue's residual: what parking lowers and does not stop. A PAUSED row is the one
           -- queue position whose spend really does stop, so it is not funded.
           SUM(IF(is_cand AND seat_no IS NULL AND move != 'PAUSE',
                  COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0))  AS queue_spend,
           -- everything the plan can see this campaign spending, whatever side it is on
           SUM(COALESCE(SAFE_DIVIDE(w_sp, window_days), 0))    AS visible_spend,
           SUM(COALESCE(w_clk, 0))                             AS visible_clicks,
           LOGICAL_OR(COALESCE(is_brand_defense, FALSE)
                      OR UPPER(COALESCE(campaign_name, '')) LIKE '%BRAND DEFENSE%')
                                                               AS is_defense,
           MAX(campaign_current_budget)                        AS current_budget,
           MAX(fam_ramp_steps)                                 AS ramp_steps
    FROM priced GROUP BY 1, 2),
  needed AS (
    SELECT i.*,
           i.implied_budget + i.queue_spend AS need_budget,
           (i.visible_spend <= 0.0001 AND i.visible_clicks = 0
            AND i.current_budget IS NOT NULL)                  AS unmeasured
    FROM implied i),
  rampd AS (
    SELECT n.*,
           GREATEST(
             COALESCE(n.current_budget, n.need_budget)
             + (n.need_budget - COALESCE(n.current_budget, n.need_budget)) / n.ramp_steps,
             n.need_budget, n.good_budget, 1.00) AS raw_budget
    FROM needed n),
  snapped AS (
    SELECT r.*,
           ROUND(
             CASE WHEN r.raw_budget > 20.00 AND r.raw_budget < 32.00
                  -- never snap a cap BELOW the money the plan can see inside this campaign
                  THEN IF(r.raw_budget < 26.00 AND r.need_budget <= 20.00, 20.00, 32.00)
                  ELSE r.raw_budget END, 2) AS ramped_budget
    FROM rampd r)
  SELECT plan, campaign_id, current_budget, need_budget, visible_spend,
         CASE WHEN is_defense OR unmeasured
                THEN ROUND(COALESCE(current_budget, ramped_budget), 2)
              ELSE ramped_budget END AS campaign_planned_budget,
         CASE WHEN is_defense                          THEN 'NO_MOVE_BRAND_DEFENSE'
              WHEN unmeasured                          THEN 'NO_MOVE_UNMEASURED'
              WHEN ramped_budget <= need_budget + 0.005
                   AND COALESCE(current_budget, need_budget) > need_budget
                                                       THEN 'FLOORED_AT_NEED'
              ELSE 'RAMPED' END AS campaign_budget_basis
  FROM snapped;

  -- THE GUARANTEES ARE ASSERTED BEFORE THE PARTITION IS TOUCHED (repaired v27.137). v27.136
  -- DELETEd, INSERTed and only then ASSERTed. BigQuery scripts are not transactional here and the
  -- orchestrator's Task 20.8c wraps this CALL in BEGIN ... EXCEPTION WHEN ERROR THEN, so a broken
  -- guarantee left the violating partition written and committed, logged one FAIL row and let the
  -- pass continue — an assertion that names a guarantee it could not protect. The rows are built
  -- into a TEMP TABLE with the fact table's own schema, the ASSERTs read that, and only a clean
  -- build reaches the partition. A failure now leaves YESTERDAY'S plan in place, which is the
  -- safe state: stale and correct beats fresh and wrong.
  CREATE OR REPLACE TEMP TABLE final AS
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE FALSE;

  INSERT INTO final
    (as_of, plan, is_live_plan, family, book, campaign_id, campaign_name, keyword_id, ad_group_id,
     target_text, match_type, channel, is_auto, is_pt, calendar_state, window_days, window_from,
     window_to, watermark, w_clk, w_ord, w_sp, w_gp, w_gp_corrected, settle_factor_min,
     settle_factor_eff, settle_curve_available, settled, settle_due_on, settle_arm, decided_by,
     was_good, family_bar, ret_raw, ret_corrected, ladder_state, side, verdict, is_candidate,
     rank_score, rank_dollars_at_stake, rank_closeness, rank_is_degenerate, served, prior_grace,
     last_grace_on, grace_limit_armed, held_despite_evidence, held_with_no_sale, good_side_no_sale,
     hold_since, hold_settles_on, hold_expired, last_day_sp, last_day_clk, last_day_ord, last_day_gp,
     last_day_gp_corrected, last_day_ret, last_day_strong, guard_released_by,
     rank_no, seat_no, seat_cost_per_day, current_bid, planned_bid, bid_floor, bid_park,
     bid_park_source, bid_park_seat_econ, move, planned_spend_per_day,
     planned_spend_delta_per_day, verdict_date, pot_per_day,
     allowance_target_per_day, allowance_ramped_per_day, notgood_today_per_day, ramp_step,
     ramp_steps, allowance_share, campaign_planned_budget, campaign_current_budget,
     campaign_planned_budget_delta_per_day, campaign_budget_basis, campaign_visible_spend_per_day,
     holdout, holdout_member, holdout_eligible_from, sentence, built_at,
     -- v27.146 (plan step 4, violation 27, §3.0 step 2): the seat names its question.
     clicks_requested, clicks_due_date, expected_cpc, implied_daily_spend, request_basis)
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
    p.hold_since, p.hold_settles_on, p.hold_expired, p.last_day_sp, p.last_day_clk, p.last_day_ord,
    p.last_day_gp, p.last_day_gp_corrected, p.last_day_ret, p.last_day_strong, p.guard_released_by,
    p.rank_no, p.seat_no,
    IF(p.side = 'GOOD', NULL, ROUND(p.plan_seat_cost, 4)),
    p.current_bid, p.planned_bid_final, p.bid_floor, p.bid_park, p.bid_park_source,
    p.bid_park_seat_econ, p.move, ROUND(p.planned_spend_per_day, 4),
    ROUND(p.planned_spend_per_day - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0), 4),
    p.verdict_date,
    ROUND(p.pot_per_day, 4), ROUND(p.allowance_target_per_day, 4),
    ROUND(p.allowance_ramped_per_day, 4), ROUND(p.notgood_today_per_day, 4),
    -- ramp_step is a REPORT: how many windows the plan has been running for this family, capped
    -- at ramp_steps. The arithmetic above does not depend on it — each night's ramp is recomputed
    -- from the actual not-good spend, so the sequence converges with or without an upload.
    LEAST(p.fam_ramp_steps,
          1 + DIV(DATE_DIFF(as_of_d, COALESCE(fs.first_as_of, as_of_d), DAY), p.window_days)),
    p.fam_ramp_steps, p.allowance_share,
    b.campaign_planned_budget, p.campaign_current_budget,
    ROUND(b.campaign_planned_budget - COALESCE(p.campaign_current_budget,
                                               b.campaign_planned_budget), 4),
    b.campaign_budget_basis, ROUND(b.visible_spend, 4),
    p.holdout, p.holdout_member, p.holdout_eligible_from,
    CONCAT(
      IF(p.plan = live_plan_code, '', 'SHADOW PLAN A, recorded for grading and never uploaded (P-9). '),
      COALESCE(p.sentence, ''), ' ', COALESCE(p.settle_arm_sentence, ''), '.',
      CASE p.move
        WHEN 'REPRICE' THEN FORMAT(
          ' SEAT %d of %s: re-price $%.2f -> $%.2f, costing about $%.2f a day of the $%.2f a day this family allows the not-good side. That is %s of about $%.2f a day against what this keyword is spending now. Judged again on %t (P-12).',
          COALESCE(p.seat_no, 0), p.family, COALESCE(p.current_bid, 0),
          COALESCE(p.planned_bid_final, 0), COALESCE(p.plan_seat_cost, 0),
          COALESCE(p.allowance_ramped_per_day, 0),
          CASE WHEN p.planned_spend_per_day
                    - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0) > 0.005 THEN 'A RAISE'
               WHEN COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)
                    - p.planned_spend_per_day > 0.005                         THEN 'a cut'
               ELSE 'no change' END,
          ABS(p.planned_spend_per_day - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)),
          COALESCE(p.verdict_date, as_of_d))
        -- THE DIRECTION CLAUSE BELONGS HERE MOST OF ALL (v27.138). A held seat's sentence says
        -- nothing is uploaded, and a reader stops there — but the seat is still COSTED at the
        -- repaired price (P-6), so the plan can have budgeted MORE for this keyword than it is
        -- spending while telling the reader there is nothing to do. v27.137 added the clause to
        -- the REPRICE sentence only and its own account said both; these are exactly the rows
        -- where the number is invisible without it.
        WHEN 'HOLD_AT_PRICE' THEN FORMAT(
          ' SEAT %d of %s: the price is already where the plan wants it, so nothing is uploaded; it keeps its seat at about $%.2f a day of the $%.2f a day this family allows the not-good side. That is %s of about $%.2f a day against what this keyword is spending now, uploaded or not. A held seat is still a seat and still carries a clock: judged again on %t (P-12), when it graduates, steps again, or gives the seat up.',
          COALESCE(p.seat_no, 0), p.family, COALESCE(p.plan_seat_cost, 0),
          COALESCE(p.allowance_ramped_per_day, 0),
          CASE WHEN p.planned_spend_per_day
                    - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0) > 0.005 THEN 'A RAISE'
               WHEN COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)
                    - p.planned_spend_per_day > 0.005                         THEN 'a cut'
               ELSE 'no change' END,
          ABS(p.planned_spend_per_day - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)),
          COALESCE(p.verdict_date, as_of_d))
        WHEN 'PARK' THEN FORMAT(
          ' QUEUED at rank %d, no seat: park the bid at $%.2f. Parking LOWERS the price, it does not stop the spend — this keyword keeps buying clicks at the park price until it earns a seat or is killed, so the real not-good spend of this family sits above the $%.2f a day allowance until then.',
          COALESCE(p.rank_no, 0), COALESCE(p.planned_bid_final, 0),
          COALESCE(p.allowance_ramped_per_day, 0))
        WHEN 'HOLD_AT_PARK' THEN FORMAT(
          ' QUEUED at rank %d, no seat — and its bid is already at or below the $%.2f park price, so there is NOTHING TO UPLOAD for this keyword: it holds its queue position at the price it already has. It is not paused and it is not dead; it keeps buying clicks at that price. A keyword that queues a whole window with no seat is a kill candidate, and the probation ladder — bid to the floor, probation, then kill — decides that, not this plan.',
          COALESCE(p.rank_no, 0), COALESCE(COALESCE(p.bid_park, p.bid_floor), 0))
        WHEN 'PAUSE' THEN FORMAT(
          ' QUEUED at rank %d, and THE LADDER HAS ALREADY CLOSED THIS KEYWORD (state DEAD): pause it. THIS SUPERSEDES THE WHOLE JUDGEMENT ABOVE — a closed keyword does not compete for a seat at any price, holds none of the family allowance, and is stopped rather than parked or re-priced, so the plan publishes no bid on this row.',
          COALESCE(p.rank_no, 0))
        WHEN 'NONE_HOLDOUT' THEN
          ' This campaign is a measurement control: the plan records what it would have done, uploads nothing to it, and leaves its money out of the pot, the not-good side and the ramp.'
        ELSE IF(p.side = 'GOOD',
          ' No move: the good side is never cut and is not re-priced (P-4), and this row carries no planned price and no seat cost.',
          ' No move: there is nothing to repair here — no spend, no clicks and no probe nomination in the window — so this keyword takes neither a seat nor a queue position (spec §9).')
      END,
      IF(p.shadow_unpriced,
         ' SHADOW PRICING NOTE: the live plan calls this keyword GOOD, so P-4 withholds a repaired price for it and the shadow holds it at its current price and costs its seat at its current spend.',
         ''),
      -- THE CAMPAIGN CAP IS ALSO A MOVE, AND IT USED TO BE THE SILENT ONE (v27.138). Every
      -- campaign in the first partition got a different cap from the one it has, and no sentence
      -- anywhere mentioned the budget. A cap is executable in a way a bid is not: it starves every
      -- keyword in the campaign, including the ones the plan never judged. So it says its number,
      -- its direction and its reason on the row, next to the keyword move.
      CASE b.campaign_budget_basis
        WHEN 'NO_MOVE_BRAND_DEFENSE' THEN FORMAT(
          ' CAMPAIGN CAP: unchanged at $%.2f a day. This is a BRAND DEFENSE campaign and defense is never judged on profit (spec §8), so the plan does not move its budget whatever the window says.',
          COALESCE(b.campaign_planned_budget, 0))
        WHEN 'NO_MOVE_UNMEASURED' THEN FORMAT(
          ' CAMPAIGN CAP: unchanged at $%.2f a day. Not one keyword the plan can see in this campaign took a click or spent a cent in the window, so the plan has MEASURED NOTHING here and says nothing about the cap. Unmeasured never reads as bad.',
          COALESCE(b.campaign_planned_budget, 0))
        ELSE FORMAT(
          ' CAMPAIGN CAP: $%.2f -> $%.2f a day, %s of $%.2f. The plan can see about $%.2f a day of spend inside this campaign (its good side, its seats at the repaired price, and the queue that keeps buying clicks at the park price) and the cap is never set below that%s.',
          COALESCE(p.campaign_current_budget, 0), COALESCE(b.campaign_planned_budget, 0),
          IF(COALESCE(b.campaign_planned_budget, 0)
             - COALESCE(p.campaign_current_budget, 0) > 0.005, 'A RAISE', 'a cut'),
          ABS(COALESCE(b.campaign_planned_budget, 0)
              - COALESCE(p.campaign_current_budget, 0)),
          COALESCE(b.need_budget, 0),
          IF(b.campaign_budget_basis = 'FLOORED_AT_NEED',
             ', which is what stopped this one going lower tonight',
             ' — tonight the one-third ramp decided it'))
      END) AS sentence,
    CURRENT_TIMESTAMP(),
    -- ------------------------------------------------------------------------------------------
    -- v27.146 — THE SEAT NAMES ITS QUESTION (violation 27, §3.0 step 2).
    -- Ori: the Brain must decide "what answers per keyword he is going to buy with it (seats) and
    -- HOW MANY CLICKS he want to deliver in a SPECIFIC TIME WINDOW."
    --
    -- NOTHING HERE IS A FORECAST. Both numbers were always implied by the seat's own dollars and
    -- were simply never written where anything could check them:
    --   ORDINARY: seat_cost = (w_sp/days) x (planned/current). At the new price CPC scales by the
    --   SAME ratio, so it cancels and the clicks bought are EXACTLY w_clk. An ordinary seat asks
    --   for the same clicks at a better price — it does not ask for more.
    --   PROBE: seat_cost = seat_cpc x click_goal_day, a goal the register already declares. A
    --   probe has always named its question; only the ordinary path was silent.
    -- click_goal_day is read from the view rather than re-declared here, so the register stays the
    -- single owner of it.
    -- NULL ON EVERY ROW WITHOUT A SEAT: a row that took no seat asked no question, and writing a
    -- target on it would invent an intention the Brain never had.
    IF(p.seat_no IS NULL, NULL,
       IF(p.is_probe, CAST(p.click_goal_day * p.window_days AS INT64),
                      CAST(p.w_clk AS INT64)))                                AS clicks_requested,
    -- THE DUE DATE IS THE SEAT'S OWN VERDICT DATE, NOT THE WINDOW'S END. window_to closes the
    -- window that was JUDGED (in the past — it is the evidence), while the seat funds the
    -- window ahead. The first cut used window_to and acceptance check S08 caught it on all 94
    -- seats: every request was already overdue on the day it was written, which would have
    -- graded as a Pacing failure that never had a chance to succeed. verdict_date is the date
    -- P-12 already promises this seat will be judged on, so the clicks are due exactly then —
    -- and it needs no new constant.
    IF(p.seat_no IS NULL, NULL, p.verdict_date)                               AS clicks_due_date,
    IF(p.seat_no IS NULL, NULL,
       ROUND(SAFE_DIVIDE(p.plan_seat_cost * p.window_days,
                         NULLIF(IF(p.is_probe, p.click_goal_day * p.window_days, p.w_clk), 0)),
             4))                                                              AS expected_cpc,
    IF(p.seat_no IS NULL, NULL, ROUND(p.plan_seat_cost, 4))                   AS implied_daily_spend,
    IF(p.seat_no IS NULL, NULL,
       IF(p.is_probe, 'PROBE_GOAL', 'WINDOW_CLICKS'))                         AS request_basis
  FROM priced p
  LEFT JOIN budgets b   ON b.plan = p.plan AND b.campaign_id = p.campaign_id
  LEFT JOIN first_seen fs ON fs.family = p.family;

  -- §9 guarantees, asserted on the rows about to be written, never on the partition after the
  -- fact. An assertion failure names the guarantee it broke — fix the arithmetic, never the
  -- assertion — and leaves the previous partition standing.
  ASSERT (SELECT COUNT(DISTINCT plan) FROM final) = 2
    AS 'both plans must be written every night (P-9)';
  -- v27.146: a seat without a question is not a seat (violation 27, §3.0 step 2).
  ASSERT (SELECT COUNTIF(seat_no IS NOT NULL
                         AND (clicks_requested IS NULL OR clicks_requested <= 0
                              OR clicks_due_date IS NULL OR request_basis IS NULL
                              OR clicks_due_date <= as_of_d))
          FROM final) = 0
    AS 'every seat names how many clicks, by a FUTURE date, and how the number was derived (violation 27)';
  ASSERT (SELECT COUNTIF(seat_no IS NULL
                         AND (clicks_requested IS NOT NULL OR clicks_due_date IS NOT NULL))
          FROM final) = 0
    AS 'a row that took no seat asked no question — no request without a seat';
  ASSERT (SELECT COUNTIF(side = 'GOOD' AND (move != 'NONE' OR planned_bid IS NOT NULL OR seat_cost_per_day IS NOT NULL))
          FROM final) = 0
    AS 'the good side is never cut, is not re-priced, and carries no executable price (P-4)';
  ASSERT (SELECT COUNTIF(seat_cost > allowance + 0.01) FROM (
            SELECT plan, family, SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                   MAX(allowance_ramped_per_day) allowance
            FROM final GROUP BY 1, 2)) = 0
    AS 'seats must fit the ramped allowance (P-2, P-8)';
  -- the other half of the same walk: nothing affordable may be left in the queue (spec §4.4)
  ASSERT (SELECT COUNTIF(min_queued <= allowance - seat_cost + 0.0001) FROM (
            SELECT plan, family, MAX(allowance_ramped_per_day) allowance,
                   SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                   -- a keyword the ladder has closed is not seatable at any price, so it is not
                   -- evidence of a prefix stop (v27.138)
                   MIN(IF(is_candidate AND seat_no IS NULL AND ladder_state != 'DEAD',
                          seat_cost_per_day, NULL)) min_queued
            FROM final GROUP BY 1, 2) WHERE min_queued IS NOT NULL) = 0
    AS 'the seat walk is a fit test: no seatable queued candidate may fit the allowance left over (§4.4)';
  -- the seat register is one authority, not two (§9)
  ASSERT (SELECT COUNT(*)
          FROM final f
          JOIN (SELECT family, CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
                       MIN(seat_no) seat_no
                FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
                WHERE closed_on IS NULL GROUP BY 1, 2, 3) l
            ON l.family = f.family AND l.seat_no = f.seat_no
          WHERE f.seat_no IS NOT NULL AND l.kid != f.keyword_id) = 0
    AS 'no seat number the register still holds OPEN may be reissued to another keyword (§9)';
  ASSERT (SELECT COUNTIF(seat_no IS NOT NULL AND (verdict_date IS NULL OR verdict_date <= as_of))
                + COUNTIF(seat_no IS NULL AND verdict_date IS NOT NULL) FROM final) = 0
    AS 'every SEAT carries a verdict date in the future, held or repriced (P-12)';
  -- P-14b / P-14c, AS THE JUDGE RULES THEM (v27.147, 2026-09-28). The v27.136 form of this
  -- assertion was `side = NOT_GOOD AND was_good AND served AND NOT settled` = 0 -- a copy of the
  -- guard's PRECONDITIONS, read as a veto. The judge (v27.138) reads P-14b as a CLOCK anchored to
  -- the window that triggered the hold, lifting when that window settles. The two agreed until
  -- the first clock expired (2026-08-29); from that night the view demoted a keyword its rule
  -- allowed and this line refused the whole partition, every night, for a month -- nothing
  -- downstream saw a plan newer than 08-28, and because nothing was written the judge's memory
  -- froze too, so the same rows failed forever. A guard that re-judges is the second engine
  -- P-11 forbids. The builder now asserts the judgement is COMPLETE, not that it agrees with a
  -- copy: every demotion of a keyword that was good, served and sits on an unsettled window
  -- carries the judge's own published release reason (HOLD_EXPIRED, or LAST_DAY_NOT_STRONG
  -- under Ori's 2026-09-17 ruling), and every row the judge holds is on the good side and
  -- earned the hold with a very good last day.
  ASSERT (SELECT COUNTIF(side = 'NOT_GOOD' AND was_good AND served AND NOT settled
                         AND guard_released_by IS NULL)
          FROM final WHERE is_live_plan) = 0
    AS 'a keyword that was good and served on an unsettled window is demoted only with the judge-published release reason: the hold clock expired, or its last day was not very good (P-14b/P-14c)';
  ASSERT (SELECT COUNTIF(verdict = 'HELD_UNSETTLED' AND (side != 'GOOD' OR NOT COALESCE(last_day_strong, FALSE)))
          FROM final WHERE is_live_plan) = 0
    AS 'every keyword the guard holds is on the good side and earned the hold with a very good last day (P-14c)';
  ASSERT (SELECT COUNTIF(holdout AND (move NOT IN ('NONE', 'NONE_HOLDOUT') OR seat_no IS NOT NULL))
          FROM final) = 0
    AS 'a holdout campaign gets a record and no move';
  -- the band rule governs a cap the plan SETS. Leaving a cap exactly where it is, on a campaign
  -- the plan measured nothing in, is not a move into the band.
  ASSERT (SELECT COUNTIF(campaign_planned_budget > 20.00 AND campaign_planned_budget < 32.00
                         AND campaign_budget_basis NOT IN
                             ('NO_MOVE_UNMEASURED', 'NO_MOVE_BRAND_DEFENSE'))
          FROM final) = 0
    AS 'no campaign budget the plan MOVES may land in the forbidden $20.01-$31.99 band';
  -- a budget that cannot pay for the money the plan can SEE is not a budget, it is a squeeze
  ASSERT (SELECT COUNTIF(bud < need - 0.005) FROM (
            SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                   SUM(planned_spend_per_day)
                   + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE',
                            COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0)) need
            FROM final GROUP BY 1, 2)
          WHERE bud IS NOT NULL) = 0
    AS 'a campaign budget may never sit under the money the plan can SEE inside it — its good side, its seats, and the queue parking does not stop (P-4)';
  -- unmeasured never reads as bad, and defense is never judged on profit (§8)
  ASSERT (SELECT COUNT(*) FROM (
            SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                   MAX(campaign_current_budget) cur, MAX(campaign_visible_spend_per_day) vis,
                   SUM(COALESCE(w_clk, 0)) clk,
                   LOGICAL_OR(UPPER(COALESCE(campaign_name, '')) LIKE '%BRAND DEFENSE%') def
            FROM final GROUP BY 1, 2)
          WHERE cur IS NOT NULL AND bud < cur - 0.005
            AND ((vis <= 0.0001 AND clk = 0) OR def)) = 0
    AS 'a campaign the plan measured nothing in, and a brand-defense campaign, may never have its budget cut';
  -- the ladder's closed keywords hold no seat, no allowance and no price (§4.5)
  ASSERT (SELECT COUNTIF(ladder_state = 'DEAD'
                         AND (seat_no IS NOT NULL OR planned_bid IS NOT NULL
                              OR (is_candidate AND move != 'PAUSE')))
          FROM final) = 0
    AS 'a keyword the ladder has closed takes no seat, carries no price, and its move is PAUSE (§4.5)';
  -- §9: seat numbers are stable across days for a continuing occupant
  ASSERT (SELECT COUNT(*)
          FROM final f
          JOIN (SELECT plan, family, CAST(campaign_id AS STRING) cid,
                       CAST(keyword_id AS STRING) kid, MIN(seat_no) seat_no
                FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                WHERE seat_no IS NOT NULL
                  AND as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                               WHERE as_of < as_of_d)
                GROUP BY 1, 2, 3, 4) h
            ON h.plan = f.plan AND h.family = f.family
           AND h.cid = f.campaign_id AND h.kid = f.keyword_id
          WHERE f.seat_no IS NOT NULL AND h.seat_no != f.seat_no
            AND NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
                            WHERE l.closed_on IS NULL AND l.family = f.family
                              AND l.seat_no = h.seat_no
                              AND CAST(l.keyword_id AS STRING) != f.keyword_id)) = 0
    AS 'a continuing occupant keeps its seat number from one night to the next unless the register reassigned it (§9)';

  DELETE FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d;
  INSERT INTO `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` SELECT * FROM final;
END;
